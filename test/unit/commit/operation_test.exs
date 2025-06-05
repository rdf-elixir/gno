defmodule Gno.CommitOperationTest do
  use GnoCase

  doctest Gno.CommitOperation

  alias Gno.CommitOperation

  describe "new/0" do
    test "creates a new commit operation with default values" do
      assert {:ok, %CommitOperation{__id__: %BlankNode{}, middlewares: []}} =
               CommitOperation.new()
    end

    test "with middlewares as classes" do
      assert {:ok,
              %CommitOperation{
                middlewares: [%Gno.CommitLogger{}, %TestStateFlowMiddleware{}]
              }} =
               CommitOperation.new(middlewares: [Gno.CommitLogger, EX.TestStateFlowMiddleware])
    end
  end
end
