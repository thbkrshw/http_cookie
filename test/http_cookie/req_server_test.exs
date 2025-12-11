defmodule ReqServerTest do
  use ExUnit.Case, async: true

  alias HttpCookie.ReqServerPlugin
  alias HttpCookie.Jar

  test "end-to-end" do
    plug =
      fn
        %{request_path: "/one"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("set-cookie", "foo=bar")
          |> Plug.Conn.resp(200, "Have a cookie")

        %{request_path: "/two"} = conn ->
          conn = Plug.Conn.fetch_cookies(conn)
          assert conn.req_cookies == %{"foo" => "bar"}

          conn
          |> Plug.Conn.prepend_resp_headers([
            {"set-cookie", "foo2=bar2"},
            {"set-cookie", "foo3=bar3"}
          ])
          |> Plug.Conn.resp(200, "Have some more")

        %{request_path: "/three"} = conn ->
          conn = Plug.Conn.fetch_cookies(conn)
          assert conn.req_cookies == %{"foo" => "bar", "foo2" => "bar2", "foo3" => "bar3"}

          conn
          |> Plug.Conn.resp(200, "No more cookies for you, come back one year")
      end

    {:ok, jar_server} = Jar.Server.start_link([])

    req =
      Req.new(base_url: "https://example.com", plug: plug)
      |> ReqServerPlugin.attach(jar_server: jar_server)

    assert %{status: 200} = Req.get!(req, url: "/one")
    assert %{status: 200} = Req.get!(req, url: "/two")
    assert %{status: 200} = Req.get!(req, url: "/three")

    jar = Jar.Server.get_cookie_jar(jar_server)

    assert %{
             "example.com" => %{
               cookies: %{
                 {"foo", "/"} => _,
                 {"foo2", "/"} => _,
                 {"foo3", "/"} => _
               }
             }
           } = jar.cookies
  end

  test "picks up cookies from redirect response" do
    plug =
      fn
        %{request_path: "/redirect-me"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("set-cookie", "redirected=yes")
          |> Plug.Conn.put_resp_header("location", "/first-stop")
          |> Plug.Conn.resp(302, "Go away")

        %{request_path: "/first-stop"} = conn ->
          conn = Plug.Conn.fetch_cookies(conn)
          assert conn.req_cookies == %{"redirected" => "yes"}

          conn
          |> Plug.Conn.put_resp_header("set-cookie", "stopped=yeah")
          |> Plug.Conn.put_resp_header("location", "/final-destination")
          |> Plug.Conn.resp(302, "Almost there")

        %{request_path: "/final-destination"} = conn ->
          conn = Plug.Conn.fetch_cookies(conn)
          assert conn.req_cookies == %{"redirected" => "yes", "stopped" => "yeah"}

          Plug.Conn.resp(conn, 200, "You made it!")
      end

    {:ok, jar_server} = Jar.Server.start_link([])

    req =
      Req.new(base_url: "https://example.com", plug: plug)
      |> ReqServerPlugin.attach(jar_server: jar_server)

    assert %{status: 200} = Req.get!(req, url: "/redirect-me")

    jar = Jar.Server.get_cookie_jar(jar_server)

    assert %{
             "example.com" => %{
               cookies: %{
                 {"redirected", "/"} => _,
                 {"stopped", "/"} => _
               }
             }
           } = jar.cookies
  end

  test "doesn't override existing cookie header" do
    plug =
      fn
        %{request_path: "/redirect-me"} = conn ->
          conn
          |> Plug.Conn.put_resp_header("set-cookie", "redirected=yes")
          |> Plug.Conn.put_resp_header("location", "/first-stop")
          |> Plug.Conn.resp(302, "Go away")

        %{request_path: "/first-stop"} = conn ->
          conn = Plug.Conn.fetch_cookies(conn)
          assert conn.req_cookies == %{"there-can-only-be" => "one"}

          conn
          |> Plug.Conn.put_resp_header("set-cookie", "stopped=yeah")
          |> Plug.Conn.put_resp_header("location", "/final-destination")
          |> Plug.Conn.resp(302, "Almost there")

        %{request_path: "/final-destination"} = conn ->
          conn = Plug.Conn.fetch_cookies(conn)
          assert conn.req_cookies == %{"there-can-only-be" => "one"}

          Plug.Conn.resp(conn, 200, "You made it!")
      end

    {:ok, jar_server} = Jar.Server.start_link([])

    req =
      Req.new(base_url: "https://example.com", plug: plug)
      |> ReqServerPlugin.attach(jar_server: jar_server)

    assert %{status: 200} =
             Req.get!(req, url: "/redirect-me", headers: [cookie: "there-can-only-be=one"])
  end
end
