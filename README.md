# Exchange [![CircleCI](https://circleci.com/gh/artsy/exchange.svg?style=svg)](https://circleci.com/gh/artsy/exchange) [![codecov](https://codecov.io/gh/artsy/exchange/branch/master/graph/badge.svg)](https://codecov.io/gh/artsy/exchange)

Exchange is responsible for the various types of e-commerce interactions available on the Artsy platform. It uses Ruby, Rails, Postgresql, and exposes a [GraphQL](http://graphql-ruby.org/) API.

## Meta

- State: production
- Production: https://exchange.artsy.net, [Admin Dashboard](https://exchange.artsy.net/admin) | [Sidekiq Dashboard](https://exchange.artsy.net/admin/sidekiq)
- Staging: https://exchange-staging.artsy.net, [Admin Dashboard](https://exchange-staging.artsy.net/admin) | [Sidekiq Dashboard](https://exchange-staging.artsy.net/admin/sidekiq)
- GitHub: https://github.com/artsy/exchange/
- Point People: [@sweir27][], [@ansor4][]
- CI/Deploys: [CircleCi](https://circleci.com/gh/artsy/exchange); merged PRs to `artsy/exchange#master` are automatically deployed to staging; PRs from `staging` to `release` are automatically deployed to production. [Start a deploy...](https://github.com/artsy/exchange/compare/release...staging?expand=1)

## Setup

- Clone the project:

  ```
  $ git clone git@github.com:artsy/exchange.git
  ```

- Read and run setup script:
  ```sh
  cat bin/setup
  bin/setup
  ```

## Tests

Once setup, you can run the tests like this:

```
$ bundle exec rspec
```

## Starting Server

Run Procfile.dev via foreman to start the web (rails) and worker (sidekiq)
services:

```bash
foreman start -f Procfile.dev
```

## Did You Change Models?

### [Papertrail Audit Logging](./docs/papertrail_audit_logging.md)

We use the [PaperTrail gem](https://github.com/paper-trail-gem/paper_trail) to maintain a log of data changes to important models within the main relational database.

### Analytics Notification

If you changed something in the `/models` make sure to inform #data (analytics) team about it in case it impacts their reports.

## Did You Change GraphQL Schema?

Metaphysics is the current consumer of Exchange GraphQL schema and keeps a copy of latest schema in https://github.com/artsy/metaphysics/tree/master/src/data, if you have changed Exchange GraphQL schema, make sure you also update the copy of this schema in Metaphysics. In order to do so follow these steps:

1. In exchange run

```shell
rake graphql:schema:idl
```

2. rename `schema.graphql` file generated ☝🏼 to `exchange.graphql`

```shell
mv schema.graphql exchange.graphql
```

3. copy file above to your local update Metaphysics under `src/data` and make a PR to Metaphysics with this change.

There is a guide on how to add exchange operations to Metaphysics [here](https://github.com/artsy/metaphysics/blob/master/docs/create_exchange_operations.md)

## Talking to Exchange 🤑

In order to talk to Exchange GraphQL endpoint:

- Copy `.env.example` to `.env`
- Update the `REPLACE` values in the `.env` file. You can reference the values used on staging with `hokusai staging env get` or use [copy_env][] to automate the task.
- Install `dotenv` by `gem install dotenv`
- Start local server `dotenv rails s`
- If you work at Artsy, get proper Gravity User Token following [these instructions](https://github.com/artsy/gravity/blob/master/doc/ApiAuthentication.md#fetching-a-user-jwt-for-the-target-service) (the client application name is "Exchange Staging").
- Install and run [GraphiQL](https://github.com/skevy/graphiql-app) app `brew cask install graphiql`
- In GraphiQL app, go to http://localhost:3000/api/graphql, you should ge unauthorized error
- Edit HTTP Headers and add `Authorization` header and set it to `Bearer <token>` where `<token>` is your Gravity token generated few steps above.

### Working at Artsy?

#### GraphQL Queries

We share our GraphQL sample queries using [Insomnia](https://insomnia.rest/) shared workspace. You can import latest queries from [environments_and_requests.json](https://github.com/artsy/potential/tree/master/insomnia)

#### Get Access To Exchange

Access to Exchange Admin is limited to users with the role "Sales Admin". Ask someone with Role Manager permissions to grant your user "Sales Admin" permissions.

### Debugging

Something went wrong? Ideally in the JSON response returned from Exchange there will be enough info to describe what went wrong. In case that was not useful, you can:

1. Check [Sentry](https://sentry.io) (password in 1Pass) and look for Exchange (staging or production) and see the error.
2. Follow exchange logs by doing

```shell
hokusai staging logs -f
```

If you think there is something we could improve in this error case, feel free to [open an issue](https://github.com/artsy/exchange/issues/new) with details about what you did and what went wrong.

## Rationale for Closed Source

This repo is closed source in order to avoid leaking potentially sensitive information about partnerships and new features through normal development.

[copy_env]: https://github.com/jonallured/copy_env
[@sweir27]: https://github.com/sweir27
[@ansor4]: https://github.com/ansor4
