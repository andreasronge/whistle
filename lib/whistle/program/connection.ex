defmodule Whistle.Program.Connection do
  alias Whistle.Program.Instance

  defstruct router: nil, name: nil, lazy_trees: %{}, vdom: {0, nil}, handlers: %{}, session: %{}

  defp handler_message(%{handlers: handlers}, name, args) do
    handlers
    |> Map.get(name, %{})
    |> Map.get(:msg)
    |> case do
      nil ->
        {:error, "handler not found"}

      handler when is_function(handler) ->
        {:ok, apply(handler, args)}

      message ->
        {:ok, message}
    end
  end

  def route(program = %{router: router, name: name, session: session}, uri) do
    %{query: query, path: path} = URI.parse(uri)
    path_info = String.split(path, "/", trim: true)

    query_params =
      if is_nil(query) do
        %{}
      else
        URI.decode_query(query)
      end

    case Instance.route(router, name, session, path_info, query_params) do
      {:ok, new_session} ->
        {:ok, %{program | session: new_session}}

      error = {:error, _} ->
        error
    end
  end

  def update(program = %{router: router, name: name, session: session}, {handler, args}) do
    with {:ok, message} <- handler_message(program, handler, args) do
      try do
        {:ok, new_session, reply} = Instance.update(router, name, message, session)
        {:ok, %{program | session: new_session}, reply}
      catch
        :exit, _value ->
          {:error, :program_crash}
      end
    end
  end

  def put_new_vdom(program = %{handlers: handlers, lazy_trees: trees, vdom: vdom}, new_vdom) do
    diff = Whistle.Html.Dom.diff(trees, vdom, new_vdom)

    handlers =
      Enum.reduce(diff.handlers, handlers, fn {:put, name, handler}, handlers ->
        Map.put(handlers, name, handler)
      end)

    new_program = %{program | vdom: new_vdom, handlers: handlers, lazy_trees: diff.lazy_trees}

    {new_program, diff.patches}
  end

  def notify_connection(%{router: router, name: name, session: session}, socket) do
    Instance.send_info(router, name, {:connected, socket, session})
  end

  def notify_disconnection(%{router: router, name: name, session: session}, socket) do
    Instance.send_info(router, name, {:disconnected, socket, session})
  end

  def view(%{router: router, name: name, session: session}) do
    Instance.view(router, name, session)
  end
end
