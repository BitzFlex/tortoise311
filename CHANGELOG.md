# Changelog

## 0.2.0 - 2018-05-28

### Added

- Experimental SSL support, please try it out and provide feedback.

- Abstract the network communication into a behaviour called
  `Tortoise.Transport`. This behaviour specify callbacks needed to
  connect, receive, and send messages using a network transport. It
  also specify setting and getting options, as well as listening using
  that network transport; the latter part is done so they can be used
  in integration tests.

- A TCP transport has been created for communicating with a broker
  using TCP. Use `Tortoise.Transport.Tcp` when specifying the server
  in the connection to use the TCP transport.

- A SSL transport `Tortoise.Transport.SSL` has been added to the
  project allowing us to connect to a broker using an encrypted
  connection.

### Removed

- The `{:tcp, 'localhost', 1883}` connection specification has been
  removed in favor of `{Tortoise.Transport.Tcp, host: 'localhost',
  port: 1883}`. This is done because we support multiple transport
  types now, such as the `Tortoise.Transport.SSL` type (which also
  takes a `key` and a `cert` option). The format is `{transport,
  opts}`.

## 0.1.0 - 2018-05-21

### Added
- The project is now on Hex which will hopefully broaden the user
  base. Future changes will be logged to this file.

- We will from now on update the version number following Semantic
  Versioning, and major changes should get logged to this file.
