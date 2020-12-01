#!/usr/bin/env ruby

require 'sinatra'
require 'puppetdb'

configure do
  set :public_folder, "./public"
end

helpers do
  def puppetdb_client
    puppetdb = ENV['PUPPETDB_URL'] || 'http://puppetdb:8080'
    PuppetDB::Client.new({server: puppetdb})
  end

  def hostinfo(data)
    certname = data["certname"]
    if puppetboard_url = ENV['PUPPETBOARD_URL']
      url = puppetboard_url.gsub('%h', certname)
                          .gsub('%e', data['environment'])
                          .gsub('%r', data['report'])
      {certname => url}
    else
      {certname => nil}
    end
  end

  def summary(field, value)
    query = [:and,
      [:'=', field, value],
      [:'=', 'latest_report?', true],
      ['in', 'certname',
        ['extract', 'certname',
          ['select_nodes',
            [:'=', 'node_state', 'active']
          ]
        ]
      ]
    ]
    response = puppetdb_client.request('events', query)

    summary = response.data.each_with_object({}) do |data, result|
      type = data["resource_type"]
      title = data["resource_title"]
      status = data["status"]
      property = data["property"]
      old_value = data["old_value"]
      new_value = data["new_value"]

      event = "#{title} [#{status}] (#{property} #{old_value} → #{new_value})"

      result[type] = {} unless result.has_key?(type)
      result[type][event] = [] unless result[type].has_key?(event)
      result[type][event] <<= hostinfo(data)
    end

    summary.sort {|a, b| a.first <=> b.first}
          .map do |key, value|
            [key, value.sort{|a,b| a.first <=> b.first}]
          end
    end
end

get "/(configuration_)?version/:version" do |version|
  result = summary('configuration_version', version)
  slim :index, :locals => { :summary => result }
end

get "/environment/:environment" do |environment|
  result = summary('environment', environment)
  slim :index, :locals => { :summary => result }
end

__END__
@@ layout
doctype html
html
  title Puppet Event Summary
  link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/uikit@3.5.10/dist/css/uikit.min.css"
  script src="https://cdn.jsdelivr.net/npm/uikit@3.5.10/dist/js/uikit.min.js"
  script src="https://cdn.jsdelivr.net/npm/uikit@3.5.10/dist/js/uikit-icons.min.js"
  body
  == yield

@@ index
div.uk-container
  div uk-filter="target: .filter"
    ul.uk-subnav.uk-subnav-pill
      li.uk-active uk-filter-control=true
        a href="#" All
      - for type, _ in summary.sort{|a,b| a.first <=> b.first}
        li uk-filter-control="filter: .#{type}"
          a href="#" = type
    ul class="filter uk-list uk-list-divider"
      - for type, events in summary.sort{|a,b| a.first <=> b.first}
        li class="#{type}"
          h2 = type
          ul.uk-list.uk-list-collapse uk-accordion="multiple: true"
            - for title, hosts in events.sort{|a, b| a.first <=> b.first}
              li
                a.uk-accordion-title.uk-text-light href="#" = title
                div.uk-accordion-content.uk-margin-remove
                  - for host in hosts.sort{|a,b| a.keys.first <=> b.keys.first}
                    ul.uk-list.uk-list-hyphen.uk-accordion-content
                      - if host.values.first.nil?
                        li = host.keys.first
                      - else
                        li
                          a href="#{host.values.first}" = host.keys.first
