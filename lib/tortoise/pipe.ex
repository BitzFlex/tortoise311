defmodule Tortoise.Pipe do
  @moduledoc """
  The transmitter "pipe", for lack of a better word, is an opaque data
  type that can be given to a process. It contains amongst other
  things a socket.

  A process can obtain a transmitter pipe by issuing a `pipe =
  Tortoise.Pipe.new(client_id)` request, which will result in a pipe
  in passive mode, meaning it will hold a socket it can publish
  messages into, but might fail, in which case it will attempt to get
  another socket from the transmitter. This all happens behind the
  scenes, it is important though that the returned pipe is used in
  future pipe requests, so publishing on a pipe should look like this:

    pipe = Tortoise.Pipe.publish(pipe, "foo/bar", "bonjour !")

  @todo, document this stuff, and document it better.
  """

  alias Tortoise.{Package, Pipe}
  alias Tortoise.Connection.{Transmitter, Inflight}

  @opaque t :: %__MODULE__{
            client_id: binary(),
            socket: port(),
            module: :tcp,
            active: boolean(),
            failure: :crash | :drop,
            timeout: non_neg_integer() | :infinity,
            pending: [reference()]
          }
  @enforce_keys [:client_id]
  defstruct([
    :client_id,
    socket: nil,
    module: :tcp,
    active: false,
    failure: :crash,
    timeout: :infinity,
    pending: []
  ])

  def new(client_id, opts \\ []) do
    active = Keyword.get(opts, :active, false)
    timeout = Keyword.get(opts, :timeout, 5000)

    opts = [timeout: timeout, active: active]

    case Transmitter.get_socket(client_id, opts) do
      {:ok, socket} ->
        %Pipe{client_id: client_id, socket: socket, active: active}

      {:error, :timeout} ->
        {:error, :timeout}
    end
  end

  def publish(%Pipe{} = pipe, topic, payload \\ nil, opts \\ []) do
    publish = %Package.Publish{
      topic: topic,
      payload: payload,
      qos: Keyword.get(opts, :qos, 0),
      retain: Keyword.get(opts, :retain, false)
    }

    with %Pipe{} = pipe <- do_publish(pipe, publish) do
      pipe
    else
      {:error, :timeout} ->
        # run pipe error spec
        {:error, :timeout}
    end
  end

  defp do_publish(%Pipe{module: :tcp} = pipe, %Package.Publish{qos: 0} = publish) do
    encoded_publish = Package.encode(publish)

    case :gen_tcp.send(pipe.socket, encoded_publish) do
      :ok ->
        pipe

      {:error, :closed} ->
        case refresh(pipe) do
          %Pipe{} = pipe ->
            do_publish(pipe, publish)

          {:error, :timeout} ->
            {:error, :timeout}
        end
    end
  end

  defp do_publish(%Pipe{client_id: client_id} = pipe, %Package.Publish{qos: qos} = publish)
       when qos in 1..2 do
    case Inflight.track(client_id, {:outgoing, publish}) do
      {:ok, ref} ->
        updated_pending = [ref | pipe.pending]
        %Pipe{pipe | pending: updated_pending}
    end
  end

  defp refresh(%Pipe{active: true, client_id: client_id} = pipe) do
    receive do
      {{Tortoise, ^client_id}, :socket, socket} ->
        %Pipe{pipe | socket: socket}
    after
      pipe.timeout ->
        {:error, :timeout}
    end
  end

  defp refresh(%Pipe{active: false} = pipe) do
    opts = [timeout: pipe.timeout, active: false]

    case Transmitter.get_socket(pipe.client_id, opts) do
      {:ok, socket} ->
        %Pipe{pipe | socket: socket}

      {:error, :timeout} ->
        {:error, :timeout}
    end
  end

  @doc """
  Await for acknowledge messages for the currently pending messages.

  Note that this enters a selective receive loop, so the await needs
  to happen before the process reaches its mailbox. It can be used in
  situations where we want to send a couple of messages and continue
  when the server has received them; This only works for messages with
  a Quality of Service above 0.
  """
  def await(pipe, timeout \\ 5000)

  def await(%Pipe{pending: []} = pipe, _timeout) do
    {:ok, pipe}
  end

  def await(%Pipe{client_id: client_id, pending: [ref | rest]} = pipe, timeout) do
    receive do
      {{Tortoise, ^client_id}, ^ref, :ok} ->
        await(%Pipe{pipe | pending: rest})
    after
      timeout ->
        {:error, :timeout}
    end
  end

  # protocols
  # defimpl Collectable do
  #   def into(pipe) do
  #     collector_fun = fn
  #       acc, {:cont, %Package.Publish{qos: 0} = elem} ->
  #         [Package.encode(elem) | acc]

  #       acc, :done ->
  #         Transmitter.publish(pipe, Enum.reverse(acc))
  #         acc

  #       _acc, :halt ->
  #         :ok
  #     end

  #     {[], collector_fun}
  #   end
  # end
end
