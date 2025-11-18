defmodule Gno.Manifest.Type do
  @moduledoc """
  Behaviour for defining manifest types.
  """

  @type t :: DCATR.Manifest.Type.t()
  @type schema :: DCATR.Manifest.Type.schema()

  defmacro __using__(_) do
    quote do
      use DCATR.Manifest.Type

      def store(opts \\ []) do
        with {:ok, service} <- service(opts), do: {:ok, service.store}
      end

      def store!(opts \\ []), do: Gno.Utils.bang!(&store/1, [opts])

      defoverridable store: 0, store: 1, store!: 0, store!: 1
    end
  end
end
