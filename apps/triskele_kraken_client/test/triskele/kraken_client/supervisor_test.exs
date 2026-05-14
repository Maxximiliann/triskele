defmodule Triskele.KrakenClient.SupervisorTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Mox

  alias Triskele.KrakenClient.HTTPClientMock

  @moduletag :phase_1

  # Valid base64 test secret (decodes to "test_secret_base64_encoded").
  # Mirrors RESTTest and AuthTest @test_secret.
  @test_secret "dGVzdF9zZWNyZXRfYmFzZTY0X2VuY29kZWQ="

  # Mox global mode: Auth's REST call and refresh Task run in GenServer
  # and Task processes — private-mode Mox would not be visible there.
  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    dets_path =
      Path.join(
        System.tmp_dir!(),
        "supervisor_test_nonce_#{System.unique_integer([:positive])}.dets"
      )

    Application.put_env(:triskele_kraken_client, :nonce_dets_path, dets_path)
    Application.put_env(:triskele_kraken_client, :http_client, HTTPClientMock)
    Application.put_env(:triskele_kraken_client, :api_key, "test_key")
    Application.put_env(:triskele_kraken_client, :api_secret, @test_secret)

    # Stub Auth's REST call for the initial token fetch during supervisor boot.
    stub(HTTPClientMock, :post, fn _url, _headers, _body ->
      body = Jason.encode!(%{"error" => [], "result" => %{"token" => "smoke_test_token"}})
      {:ok, 200, body}
    end)

    on_exit(fn ->
      Application.delete_env(:triskele_kraken_client, :nonce_dets_path)
      Application.delete_env(:triskele_kraken_client, :http_client)
      Application.delete_env(:triskele_kraken_client, :api_key)
      Application.delete_env(:triskele_kraken_client, :api_secret)
      File.rm(dets_path)
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts all 8 children and each child is alive" do
      sup_pid = start_supervised!(Triskele.KrakenClient.Supervisor)

      children = Supervisor.which_children(sup_pid)

      assert length(children) == 8

      for {_id, child_pid, _type, _modules} <- children do
        assert is_pid(child_pid), "expected a PID, got #{inspect(child_pid)}"
        assert Process.alive?(child_pid), "child process #{inspect(child_pid)} is not alive"
      end
    end
  end
end
