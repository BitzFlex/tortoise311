# Changelog

## 0.4.3 - 2018-07-17

### Changed

- The wrong field was pulled out of the configuration options when the
  last will message was set, so it was impossible to configure a last
  will message. The last will message can now be set by passing in a
  `%Tortoise.Package.Publish{}` struct as the `:will` when starting a
  connection.

## 0.4.2 - 2018-07-08

### Changed

- The `Tortoise.Connection.renew/1` will now return `:ok` on success;
  allowing the `Torotise.Connection.Receiver` to not crash on its
  assertion when it request a reconnect.

## 0.4.1 - 2018-07-08

### Changed

- Tortoise should now survive the server it is connected to being
  restarted. `{:error, :econnrefused}` and `{:error, :closed}` has
  been added to the errors that make tortoise attempt a reconnect.

## 0.4.0 - 2018-07-08

### Added

- Incremental backoff has been added to the connector, allowing us to
  retry reconnecting to the broker if the initial (or later reconnect)
  attempt fails. The backoff will per default start retrying after 100
  ms and it will increment in multiples of 2 up until 30 seconds, at
  which point it will flip back to 100 ms and start over. This should
  ensure that we will be able to connect fairly quickly if it is a
  network fluke (or the network devise is not ready yet), and still
  not try *too often* or *too quickly*.

  The backoff can be configured by passing `backoff` containing a
  keyword list to the connection specification. Example `backoff:
  [min_interval: 100, max_interval: 30_000]`. Both times are in
  milliseconds.

### Changed

- The code for establishing a connection and eventually reconnecting
  has been combined into one. This makes it easier to test and verify,
  and it will make it easier to handle connection errors.

  Because the initial connection is happening outside of the `init/1`
  function the possible return values of the
  `Tortoise.Connection.start_link/1`-function has changed a bit. A
  fatal error will cause the connection process to exit instead
  because the init will always return `{:ok, state}`. This might break
  some implementation using Tortoise.

  For now it is only `{:error, :nxdomain}` that is handled with
  connection retries. Error categorization has been planned so we can
  error out if it is a non-recoverable error reason (such as no cacert
  files specified), instead of retrying the connection. In the near
  future more error reasons will be handled with reconnect attempts.

- A protocol violation from the server during connection will be
  handled better; previously it would error with a decoding error,
  because it would attempt to decode 4 random bytes. The error message
  should be obvious now.

## 0.3.0 - 2018-06-10

### Added

- Thanks to [Troels Brødsgaard](https://github.com/trarbr) Tortoise
  now implement a module for its registry. This is found in
  `Tortoise.Registry`.

- The user defined controller handler callback module now accept "next
  actions" in the return tuple; this allow the user to specify that a
  topic should get subscribed to, or unsubscribed from, by specifying
  a return like `{:ok, new_state, [{:subscribe, "foo/bar", qos: 3},
  {:unsubscribe, "baz/quux"}]}`.

  This is needed as the controller must not be blocked, and the user
  defined callback module run in the context of the controller. By
  allowing next actions like this the user can subscribe and
  unsubscribe to topics when certain events happen.

- The test coverage tool will now ignore modules found in the
  *lib/tortoise/handlers/*-folder. These modules implement the
  `Tortoise.Handler`-behaviour, so they should be good.

### Changed

- `Tortoise.subscribe/3` is now async, so a message will get sent to
  the mailbox of the calling process. The old behavior can be found in
  the newly created `Tortoise.subscribe_sync/3` that will block until
  the server has acknowledged the subscribe.

- `Tortoise.unsubscribe/3` is now also async, so like the subscribe a
  message will get sent to the mailbox of the calling process. The old
  behavior can be found in the newly added
  `Tortoise.unsubscribe_sync/3` that will block until the server has
  acknowledged the subscribe.

- A major refactorization of the code handling the logic running the
  user defined controller callbacks has been lifted from the
  `Tortoise.Connection.Controller` and put into the `Tortoise.Handler`
  module. This change made it possible to support the next actions,
  and makes it much easier test and add new next action types in the
  future.

## 0.2.2 - 2018-05-29

### Changed

- Fix an issue where larger messages would crash the receiver. It has
  been fixed and tested with messages as large as 268435455 bytes;
  which is a pretty big MQTT message.

## 0.2.1 - 2018-05-29

### Added

- The `Tortoise.Transport.SSL` will now pass in `[verify:
  :verify_peer]` as the default option when connecting. This will
  guide the user to pass in a list of trusted CA certificates, such as
  one provided by the Certifi package, or opt out of this by passing
  the `verify: :verify_none` option; this will make it hard for the
  user to make unsafe choices.

  Thanks to [Bram Verburg](https://github.com/voltone) for this
  improvement.

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
