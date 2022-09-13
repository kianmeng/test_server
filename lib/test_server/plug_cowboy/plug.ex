defmodule TestServer.Plug.Cowboy.Plug do
  @moduledoc false

  alias Plug.Conn
  alias TestServer.Instance

  def init([instance]), do: instance

  def call(conn, instance) do
    case Instance.dispatch(instance, {:plug, conn}) do
      {:ok, %{adapter: {adapter, req}, private: %{websocket: {socket, state}}} = conn} ->
        conn
        |> Map.put(:state, :chunked)
        |> Map.put(:adapter, {adapter, {:websocket, req, {socket, state}}})

      {:ok, conn} ->
        conn

      {:error, {:not_found, conn}} ->
        message =
          "Unexpected #{conn.method} request received at #{conn.request_path}"
          |> append_params(conn)
          |> format_active_routes(instance)

        resp_error(conn, instance, {RuntimeError.exception(message), []})

      {:error, {error, stacktrace}} ->
        resp_error(conn, instance, {error, stacktrace})
    end
  end

  defp append_params(message, conn) do
    conn
    |> Map.take([:query_params, :body_params])
    |> Enum.filter(fn
      {_key, %Conn.Unfetched{}} -> false
      {_key, empty} when empty == %{} -> false
      {_key, params} when is_map(params) -> true
    end)
    |> case do
      [] -> message <> "."
      params -> message <> " with params:\n\n#{inspect(Map.new(params), pretty: true)}"
    end
  end

  defp format_active_routes(message, instance) do
    active_routes = Enum.reject(Instance.routes(instance), & &1.suspended)

    format_active_routes(message, active_routes, instance)
  end

  defp format_active_routes(message, [], instance),
    do: message <> "\n\nNo active routes for #{inspect(Instance)} #{inspect(instance)}"

  defp format_active_routes(message, active_routes, instance) do
    message <>
      "\n\nActive routes for #{inspect(Instance)} #{inspect(instance)}:\n\n#{Instance.format_routes(active_routes)}"
  end

  defp resp_error(conn, instance, {exception, stacktrace}) do
    Instance.report_error(instance, {exception, stacktrace})

    Conn.send_resp(conn, 500, Exception.format(:error, exception, stacktrace))
  end

  def default_plug, do: &Conn.fetch_query_params/1
end