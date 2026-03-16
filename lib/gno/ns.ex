defmodule Gno.NS do
  @moduledoc """
  `RDF.Vocabulary.Namespace`s for the used vocabularies within Gno.
  """

  use RDF.Vocabulary.Namespace

  @vocabdoc """
  The Gno vocabulary.

  See <https://w3id.org/gno/spec>
  """
  defvocab Gno,
    base_iri: "https://w3id.org/gno#",
    file: "gno.ttl",
    case_violations: :fail

  @vocabdoc """
  The Gno store adapter vocabulary.
  """
  defvocab GnoA,
    base_iri: "https://w3id.org/gno/store/adapter/",
    file: "gno_store_adapter.ttl",
    terms: [],
    strict: false

  @prefixes RDF.prefix_map(
              gno: __MODULE__.Gno,
              gnoa: __MODULE__.GnoA,
              dcatr: DCATR,
              dcat: DCAT,
              prov: PROV,
              skos: SKOS,
              foaf: FOAF
            )

  @doc """
  Returns the default `RDF.PrefixMap` with all Gno-related namespace prefixes.
  """
  def prefixes, do: @prefixes

  @doc """
  Returns a `RDF.PrefixMap` limited to the given prefix names.
  """
  def prefixes(filter), do: RDF.PrefixMap.limit(@prefixes, filter)
end
