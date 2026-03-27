# ── Stage 1: Build assets ──────────────────────────────
FROM node:20-slim AS assets
WORKDIR /build
COPY package.json yarn.lock* ./
RUN yarn install --frozen-lockfile
COPY . .
RUN yarn build && yarn build:css

# ── Stage 2: Build gems ────────────────────────────────
FROM ruby:3.3.4-slim AS gems
RUN apt-get update -qq && apt-get install -y \
  build-essential libpq-dev git \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /rails
COPY Gemfile Gemfile.lock* ./
RUN bundle config set --local deployment true \
  && bundle config set --local without 'development test' \
  && bundle install --jobs 4

# ── Stage 3: Production image ──────────────────────────
FROM ruby:3.3.4-slim AS production

RUN apt-get update -qq && apt-get install -y \
  libpq5 curl \
  && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash rails
WORKDIR /rails

COPY --from=gems /rails/vendor /rails/vendor
COPY --from=gems /usr/local/bundle /usr/local/bundle
COPY --from=assets /build/public/assets /rails/public/assets
COPY --from=assets /build/public/builds /rails/public/builds
COPY . .

RUN chown -R rails:rails /rails
USER rails

ENV RAILS_ENV=production
ENV BUNDLE_DEPLOYMENT=true
ENV BUNDLE_WITHOUT=development:test

EXPOSE 3000

ENTRYPOINT ["./docker/entrypoint.sh"]
CMD ["bundle", "exec", "thrust", "bundle", "exec", "puma", "-C", "config/puma.rb"]
