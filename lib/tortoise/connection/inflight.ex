defmodule Tortoise.Connection.Inflight do
  @moduledoc false

  alias Tortoise.{Package, Connection}
  alias Tortoise.Connection.Controller
  alias Tortoise.Connection.Inflight.Track

  use GenServer

  @enforce_keys [:client_id]
  defstruct pending: %{}, connection: nil, client_id: nil

  alias __MODULE__, as: State

  # Client API
  def start_link(opts) do
    client_id = Keyword.fetch!(opts, :client_id)
    GenServer.start_link(__MODULE__, opts, name: via_name(client_id))
  end

  defp via_name(client_id) do
    Tortoise.Registry.via_name(__MODULE__, client_id)
  end

  def stop(client_id) do
    GenServer.stop(via_name(client_id))
  end

  def track(client_id, {:incoming, %Package.Publish{qos: qos, dup: false} = publish})
      when qos in 1..2 do
    :ok = GenServer.cast(via_name(client_id), {:incoming, publish})
  end

  def track(client_id, {:outgoing, package}) do
    caller = {_, ref} = {self(), make_ref()}

    case package do
      %Package.Publish{qos: qos} when qos in 1..2 ->
        :ok = GenServer.cast(via_name(client_id), {:outgoing, caller, package})
        {:ok, ref}

      %Package.Subscribe{} ->
        :ok = GenServer.cast(via_name(client_id), {:outgoing, caller, package})
        {:ok, ref}

      %Package.Unsubscribe{} ->
        :ok = GenServer.cast(via_name(client_id), {:outgoing, caller, package})
        {:ok, ref}
    end
  end

  def track_sync(client_id, {:outgoing, _} = command, timeout \\ :infinity) do
    {:ok, ref} = track(client_id, command)

    receive do
      {{Tortoise, ^client_id}, ^ref, result} ->
        result
    after
      timeout -> {:error, :timeout}
    end
  end

  def update(client_id, {_, %{__struct__: _, identifier: _identifier}} = event) do
    :ok = GenServer.cast(via_name(client_id), {:update, event})
  end

  # Server callbacks
  def init(opts) do
    client_id = Keyword.fetch!(opts, :client_id)
    initial_state = %State{client_id: client_id}

    send(self(), :post_init)
    {:ok, initial_state}
  end

  def handle_info(:post_init, state) do
    case Connection.connection(state.client_id, active: true) do
      {:ok, {_transport, _socket} = connection} ->
        {:noreply, %State{state | connection: connection}}

      {:error, :timeout} ->
        {:stop, :connection_timeout, state}

      {:error, :unknown_connection} ->
        {:stop, :unknown_connection, state}
    end
  end

  def handle_info(
        {{Tortoise, client_id}, :socket, {transport, socket}},
        %State{client_id: client_id} = state
      ) do
    {:noreply, %State{state | connection: {transport, socket}}}
  end

  def handle_cast({:incoming, package}, %{pending: pending} = state) do
    track = Track.create(:positive, package)
    updated_pending = Map.put_new(pending, track.identifier, track)

    case execute(track, %State{state | pending: updated_pending}) do
      {:ok, state} ->
        {:noreply, state}
    end
  end

  def handle_cast({:outgoing, caller, package}, %{pending: pending} = state) do
    {:ok, package} = assign_identifier(package, pending)
    track = Track.create({:negative, caller}, package)
    updated_pending = Map.put_new(pending, track.identifier, track)

    case execute(track, %State{state | pending: updated_pending}) do
      {:ok, state} ->
        {:noreply, state}
    end
  end

  def handle_cast({:update, update}, state) do
    {:ok, next_action, state} = progress_track_state(update, state)

    case execute(next_action, state) do
      {:ok, state} ->
        {:noreply, state}
    end
  end

  # helpers

  defp execute(
         %Track{pending: [{:dispatch, package} | _]},
         %State{connection: {transport, socket}} = state
       ) do
    case apply(transport, :send, [socket, Package.encode(package)]) do
      :ok ->
        update = {:dispatched, package}
        {:ok, next_action, state} = progress_track_state(update, state)
        execute(next_action, state)
    end
  end

  defp execute(%Track{pending: [{:expect, _package} | _]}, state) do
    # await the package in a later update
    {:ok, state}
  end

  defp execute(%Track{pending: []} = track, state) do
    :ok = Controller.handle_result(state.client_id, track)
    pending = Map.delete(state.pending, track.identifier)
    {:ok, %State{state | pending: pending}}
  end

  defp progress_track_state({_, package} = input, %State{} = state) do
    # todo, handle possible error
    {next_action, updated_pending} =
      Map.get_and_update!(state.pending, package.identifier, fn track ->
        updated_track = Track.update(track, input)
        {updated_track, updated_track}
      end)

    {:ok, next_action, %State{state | pending: updated_pending}}
  end

  # Assign a random identifier to the tracked package; this will make
  # sure we pick a random number that is not in use
  defp assign_identifier(%{identifier: nil} = package, pending) do
    case :crypto.strong_rand_bytes(2) do
      <<0, 0>> ->
        # an identifier cannot be zero
        assign_identifier(package, pending)

      <<identifier::integer-size(16)>> ->
        unless Map.has_key?(pending, identifier) do
          {:ok, %{package | identifier: identifier}}
        else
          assign_identifier(package, pending)
        end
    end
  end

  # ...as such we should let the in-flight process assign identifiers,
  # but the possibility to pass one in has been kept so we can make
  # deterministic unit tests
  defp assign_identifier(%{identifier: identifier} = package, pending)
       when identifier in 0x0001..0xFFFF do
    unless Map.has_key?(pending, identifier) do
      {:ok, package}
    else
      {:error, {:identifier_already_in_use, identifier}}
    end
  end
end
