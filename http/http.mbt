// Copyright 2025 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
pub(all) enum Method {
  Get
  Head
  Post
  Put
  Delete
  Connect
  Options
  Trace
  Patch
}

///|
fn Method::to_wasi(self : Method) -> @types.Method {
  match self {
    Get => @types.Method::Get
    Head => @types.Method::Head
    Post => @types.Method::Post
    Put => @types.Method::Put
    Delete => @types.Method::Delete
    Connect => @types.Method::Connect
    Options => @types.Method::Options
    Trace => @types.Method::Trace
    Patch => @types.Method::Patch
  }
}

///|
pub(all) enum Scheme {
  Http
  Https
}

///|
fn Scheme::to_wasi(self : Scheme) -> @types.Scheme {
  match self {
    Http => @types.Scheme::Http
    Https => @types.Scheme::Https
  }
}

///|
pub(all) struct Response {
  status : Int
  headers : Map[String, String]
}

///|
pub(all) suberror HttpError {
  RequestFailed(@types.ErrorCode)
  InvalidResponse
  StreamError
}

///|
impl Show for HttpError with output(self, logger) {
  match self {
    RequestFailed(code) => logger.write_string("HttpError::RequestFailed(\{code})")
    InvalidResponse => logger.write_string("HttpError::InvalidResponse")
    StreamError => logger.write_string("HttpError::StreamError")
  }
}

///|
priv struct UrlParts {
  scheme : Scheme
  authority : String
  path : String
}

///|
fn parse_url(url : String) -> UrlParts {
  let chars = url.to_array()
  let len = chars.length()

  // Check for https://
  if len >= 8 {
    let prefix = String::from_array(chars[:8].to_array())
    if prefix == "https://" {
      let rest = String::from_array(chars[8:].to_array())
      let (authority, path) = split_authority_path(rest)
      return { scheme: Https, authority, path }
    }
  }

  // Check for http://
  if len >= 7 {
    let prefix = String::from_array(chars[:7].to_array())
    if prefix == "http://" {
      let rest = String::from_array(chars[7:].to_array())
      let (authority, path) = split_authority_path(rest)
      return { scheme: Http, authority, path }
    }
  }

  // Default to https
  let (authority, path) = split_authority_path(url)
  { scheme: Https, authority, path }
}

///|
fn split_authority_path(s : String) -> (String, String) {
  let chars = s.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '/' {
      return (String::from_array(chars[:i].to_array()), String::from_array(chars[i:].to_array()))
    }
  }
  (s, "/")
}

///|
fn extract_headers(fields : @types.Fields) -> Map[String, String] {
  let result : Map[String, String] = {}
  for entry in fields.entries() {
    let (name, value) = entry
    result[name] = String::from_array(value.map(fn(b) { b.to_int().unsafe_to_char() }))
  }
  fields.drop()
  result
}

///|
async fn write_all_to_stream(stream : @streams.OutputStream, data : Bytes) -> Unit {
  let mut offset = 0
  while offset < data.length() {
    let pollable = stream.subscribe()
    @ev.suspend_for_pollable(pollable)
    let can_write = stream.check_write().unwrap().to_int()
    if can_write > 0 {
      let chunk_size = @cmp.minimum(can_write, data.length() - offset)
      let chunk = FixedArray::makei(chunk_size, fn(i) { data[offset + i] })
      stream.write(chunk).unwrap()
      offset += chunk_size
    }
  }
  stream.flush().unwrap()
  let pollable = stream.subscribe()
  @ev.suspend_for_pollable(pollable)
}

///|
async fn read_body(incoming_body : @types.IncomingBody) -> Bytes {
  let stream = incoming_body.stream().unwrap()
  let chunks : Array[Bytes] = []
  while true {
    let pollable = stream.subscribe()
    @ev.suspend_for_pollable(pollable)
    match stream.read(65536) {
      Ok(data) => {
        if data.length() > 0 {
          chunks.push(Bytes::from_array(data))
        }
      }
      Err(@streams.StreamError::Closed) => break
      Err(_) => break
    }
  }
  stream.drop()
  incoming_body.finish().drop()
  // Note: incoming_body is consumed by finish(), no need to drop

  // Concatenate chunks
  let total_len = chunks.iter().fold(init=0, fn(acc, chunk) { acc + chunk.length() })
  let arr : FixedArray[Byte] = FixedArray::make(total_len, b'\x00')
  let mut offset = 0
  for chunk in chunks {
    for i = 0; i < chunk.length(); i = i + 1 {
      arr[offset + i] = chunk[i]
    }
    offset += chunk.length()
  }
  Bytes::from_array(arr)
}

///|
/// Perform an HTTP request and return the response with body.
pub async fn request(
  meth : Method,
  url : String,
  headers~ : Map[String, String] = {},
  body~ : Bytes = Bytes::make(0, 0),
) -> (Response, Bytes) {
  // Parse URL
  let url_parts = parse_url(url)

  // Create headers
  let fields = @types.Fields::fields()
  for k, v in headers {
    let v_bytes = v.to_array().map(fn(c) { c.to_int().to_byte() })
    fields.append(k, FixedArray::from_array(v_bytes)).unwrap()
  }

  // Create request
  let req = @types.OutgoingRequest::outgoing_request(fields)
  req.set_method(meth.to_wasi()).unwrap()
  req.set_scheme(Some(url_parts.scheme.to_wasi())).unwrap()
  req.set_authority(Some(url_parts.authority)).unwrap()
  req.set_path_with_query(Some(url_parts.path)).unwrap()

  // Write body if present
  let outgoing_body = req.body().unwrap()
  if body.length() > 0 {
    let stream = outgoing_body.write().unwrap()
    write_all_to_stream(stream, body)
    stream.drop()
  }
  outgoing_body.finish(None).unwrap()

  // Send request
  let future_response = match @outgoingHandler.handle(req, None) {
    Ok(f) => f
    Err(e) => raise HttpError::RequestFailed(e)
  }
  // Note: req ownership is transferred to handle, no need to drop

  // Wait for response
  let pollable = future_response.subscribe()
  @ev.suspend_for_pollable(pollable)

  let result = future_response.get()
  future_response.drop()

  let incoming_response = match result {
    Some(Ok(Ok(resp))) => resp
    Some(Ok(Err(e))) => raise HttpError::RequestFailed(e)
    Some(Err(_)) => raise HttpError::InvalidResponse
    None => raise HttpError::InvalidResponse
  }

  // Extract response
  let status = incoming_response.status().reinterpret_as_int()
  let response_headers = extract_headers(incoming_response.headers())

  // Read body
  let incoming_body = incoming_response.consume().unwrap()
  let body_data = read_body(incoming_body)
  incoming_response.drop()

  (Response::{ status, headers: response_headers }, body_data)
}

///|
/// Perform an HTTP GET request.
pub async fn get(
  url : String,
  headers~ : Map[String, String] = {},
) -> (Response, Bytes) {
  request(Get, url, headers~)
}

///|
/// Perform an HTTP POST request.
pub async fn post(
  url : String,
  body : Bytes,
  headers~ : Map[String, String] = {},
) -> (Response, Bytes) {
  request(Post, url, headers~, body~)
}

///|
/// Perform an HTTP PUT request.
pub async fn put(
  url : String,
  body : Bytes,
  headers~ : Map[String, String] = {},
) -> (Response, Bytes) {
  request(Put, url, headers~, body~)
}
