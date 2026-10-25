skip_if_not_installed("callr")
skip_if_not_installed("httpuv")
skip_if_not_installed("jsonlite")
library(httr2)

handler <- function(req) {
  if (req$method == "GET" && req$path == "/greet") {
    list(
      status = 200L,
      body = '{"hello":"world"}',
      headers = list(`Content-Type` = "application/json")
    )
  } else if (req$method == "POST" && req$path == "/count") {
    body <- jsonlite::fromJSON(rawToChar(req$body))$number
    list(
      status = 201L,
      body = jsonlite::toJSON(list(result = body + 1), auto_unbox = TRUE),
      headers = list(`Content-Type` = "application/json")
    )
  } else {
    list(
      status = 404L,
      body = '{"error":"not found"}'
    )
  }
}

srv <- start_mock("http-test", handler = handler, n = 3)
on.exit(srv$kill())

proxy <- np_proxy("http-test")
on.exit(proxy$proc$kill(), add = TRUE)

test_that("proxy can relay HTTP requests", {
  resp <- request(proxy$base_url) %>%
    req_url_path("/greet") %>%
    req_perform() %>%
    resp_body_json()
  expect_equal(resp, list(hello = "world"))
})


test_that("proxy can relay POST requests", {
  resp <- request(proxy$base_url) %>%
    req_url_path("/count") %>%
    req_body_json(list(number = 5)) %>%
    req_perform() %>%
    resp_body_json()
  expect_equal(resp, list(result = 6))
})


test_that("proxy can relay HTTP errors", {
  req <- request(proxy$base_url) %>%
    req_url_path("/error") %>%
    req_method("PATCH")
  expect_error(req_perform(req), "HTTP 404")
})