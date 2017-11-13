defmodule FT.Web.TaggedApiKeyTest do
  @moduledoc false

  use ExUnit.Case
  use Plug.Test

  alias FT.Web.TaggedApiKeyPlug

  def get_val(val), do: val

  describe "configuration" do

    @tag :configuration
    test "configuration defaults" do
        config =  TaggedApiKeyPlug.init([keys: "api-key"])

        %{header: "x-api-key", metrics: false} = config
    end

    @tag :configuration
    test "configuration with custom header" do
        config =  TaggedApiKeyPlug.init([header: "my-header", keys: "api-key"])

        %{header: "my-header"} = config
    end

    @tag :configuration
    test "configuration with custom metrics" do
        config =  TaggedApiKeyPlug.init([keys: "api-key", metrics: Foo])

        %{metrics: Foo} = config
    end

    @tag :configuration
    test "configuration with metrics disabled" do
        config =  TaggedApiKeyPlug.init([keys: "api-key", metrics: false])

        %{metrics: false} = config
    end

    @tag :configuration
    test "configuration with tuple" do
        mfa = {__MODULE__, :get_val, ["xyzzy"]}
        config =  TaggedApiKeyPlug.init([keys: mfa])

        %{keys: ^mfa} = config
    end

    @tag :configuration
    test "configuration with string" do
      key = "yyzzx"
      config =  TaggedApiKeyPlug.init([keys: key])

      %{keys: ^key} = config
    end

    @tag :configuration
    test "missing keys configuration raises ArgumentError" do
        assert_raise ArgumentError, fn ->  TaggedApiKeyPlug.init([header: "my-header"]) end
    end
  end

  describe "key validation" do

    @tag :api_key
    test "valid api key" do
        conn = call([keys: "XYZZY"], "XYZZY")

        assert conn.assigns.api_key == "XYZZY"
        assert conn.private.authentication
        assert conn.private.authentication == %{method: :api_key, key: "XYZZY", roles: %{}}
    end

    @tag :api_key
    test "valid api key with tag" do
        conn = call([keys: "XYZZY<>my_tag"], "XYZZY")

        assert conn.assigns.api_key == "XYZZY"
        assert conn.assigns.auth_tags == %{my_tag: true}
        assert conn.private.authentication
        assert conn.private.authentication == %{method: :api_key, key: "XYZZY", roles: %{my_tag: true}}
      end

    @tag :api_key
    test "valid api key with tags" do
        conn = call([keys: "XYZZY<>my_tag<>another"], "XYZZY")

        assert conn.assigns.api_key == "XYZZY"
        assert conn.assigns.auth_tags == %{my_tag: true, another: true}
        assert conn.private.authentication
        assert conn.private.authentication == %{method: :api_key, key: "XYZZY", roles: %{my_tag: true, another: true}}
    end

    @tag :api_key
    test "valid api key, multiple comma-sparated keys" do

        ["XYZZY", "YYZZX"]
        |> Enum.map(fn key ->
            try do
                conn = call([keys: "SECRET,XYZZY,YYZZX"], key)
                assert conn.assigns.api_key == key
                assert conn.private.authentication
                assert conn.private.authentication == %{method: :api_key, key: key, roles: %{}}

              rescue
                _ in FT.Web.Errors.ForbiddenError -> flunk("Unexpected Forbidden for key #{key}")
            end
        end)
    end

    @tag :api_key
    test "invalid api key" do
        assert_raise FT.Web.Errors.ForbiddenError, fn -> call([keys: "WRONGKEY"], "XYZZY") end
    end

    @tag :api_key
    test "no api key" do
        conn = conn(:get, "/foo", "bar=10")

        assert_raise FT.Web.Errors.ForbiddenError, fn ->  TaggedApiKeyPlug.call(conn, %{header: "x-header", keys: "XYZZY", metrics: false}) end
    end

    @tag :api_key
    test "keys specified by MFA" do
        Application.put_env(:my_app, :api_key, "XYZZY")

        config = [keys: {Application, :get_env, [:my_app, :api_key]}]

        conn = call(config, "XYZZY")
        assert conn.assigns.api_key == "XYZZY"

        assert_raise FT.Web.Errors.ForbiddenError, fn -> call(config, "ZXYYX") end
    end

  end

  defmodule TestMetrics do
    @behaviour FT.Web.ApiKeyMetrics

    @impl true
    def record_usage(conn, api_key) do
      send(self(), {:metrics, api_key})
      conn
    end
  end


  describe "metrics" do
    @tag :metrics
    test "recorded for valid api key" do
      config = TaggedApiKeyPlug.init(keys: "XYZZY", metrics: TestMetrics)

      conn = conn(:get, "/")
      |> put_req_header("x-api-key", "XYZZY")
      |> TaggedApiKeyPlug.call(config)

      assert conn.private.authentication
      assert_received {:metrics, "XYZZY"}
    end

    @tag :metrics
    test "not recorded for for invalid api key" do
      config = TaggedApiKeyPlug.init(keys: "XYZZY", metrics: TestMetrics)

      conn = conn(:get, "/")
      |> put_req_header("x-api-key", "ZYXXY")

      assert_raise FT.Web.Errors.ForbiddenError, fn -> TaggedApiKeyPlug.call(conn, config) end

      refute_received {:metrics, _}
    end
  end

  defp call(config, key, header \\ "x-api-key") do
    config =
      config
      |> Keyword.put_new(:header, header)
      |> Keyword.put_new(:metrics, false)
      |>  TaggedApiKeyPlug.init()

    conn(:get, "/foo", "bar=10")
    |> put_req_header(header, key)
    |>  TaggedApiKeyPlug.call(config)
  end

end