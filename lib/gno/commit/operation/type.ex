defmodule Gno.CommitOperation.Type do
  alias Gno.Commit.Processor

  @type t :: Grax.Schema.t()

  @callback new(RDF.Resource.t(), args :: keyword) :: t()

  @callback default :: t()

  @callback init(Processor.t()) :: {:ok, Processor.t()} | {:error, any()}

  @callback commit_id(Processor.t()) :: {:ok, RDF.Resource.t()} | {:error, any()}

  @callback add_metadata(Processor.t()) :: {:ok, Processor.t()} | {:error, any()}

  @callback result(Processor.t()) :: {:ok, any()} | {:error, any()}
end
