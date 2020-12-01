FROM ruby:2.7

ENV APP_ENV=production

COPY . /app
WORKDIR /app

RUN bundle install

EXPOSE 4567
CMD ruby app.rb
