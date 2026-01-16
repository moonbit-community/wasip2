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
pub(all) suberror SocketError {
  NetworkError(@wasiNetwork.ErrorCode)
  StreamError
}

///|
impl Show for SocketError with output(self, logger) {
  match self {
    NetworkError(code) => logger.write_string("SocketError::NetworkError(\{code})")
    StreamError => logger.write_string("SocketError::StreamError")
  }
}

///|
/// IPv4 address
pub(all) struct Ipv4Addr {
  a : Byte
  b : Byte
  c : Byte
  d : Byte
}

///|
/// IPv6 address
pub(all) struct Ipv6Addr {
  segments : (UInt, UInt, UInt, UInt, UInt, UInt, UInt, UInt)
}

///|
/// IP address (IPv4 or IPv6)
pub(all) enum IpAddr {
  V4(Ipv4Addr)
  V6(Ipv6Addr)
}

///|
/// Socket address (IP + port)
pub(all) struct SocketAddr {
  ip : IpAddr
  port : UInt
}

///|
fn SocketAddr::to_wasi(self : SocketAddr) -> @wasiNetwork.IpSocketAddress {
  match self.ip {
    V4(addr) => @wasiNetwork.IpSocketAddress::Ipv4({
      port: self.port,
      address: (addr.a, addr.b, addr.c, addr.d),
    })
    V6(addr) => @wasiNetwork.IpSocketAddress::Ipv6({
      port: self.port,
      flow_info: 0U,
      address: addr.segments,
      scope_id: 0U,
    })
  }
}

///|
/// TCP stream for connected sockets
pub(all) struct TcpStream {
  priv socket : @tcp.TcpSocket
  priv input : @streams.InputStream
  priv output : @streams.OutputStream
}

///|
/// Connect to a TCP server at the given address.
pub async fn tcp_connect(addr : SocketAddr) -> TcpStream {
  let network = @instanceNetwork.instance_network()

  // Create socket based on address family
  let address_family = match addr.ip {
    V4(_) => @wasiNetwork.IpAddressFamily::IPV4
    V6(_) => @wasiNetwork.IpAddressFamily::IPV6
  }
  let socket = match @tcpCreateSocket.create_tcp_socket(address_family) {
    Ok(s) => s
    Err(e) => raise SocketError::NetworkError(e)
  }

  // Start connect
  match socket.start_connect(network, addr.to_wasi()) {
    Ok(_) => ()
    Err(e) => {
      socket.drop()
      network.drop()
      raise SocketError::NetworkError(e)
    }
  }

  // Wait for connection
  let pollable = socket.subscribe()
  @ev.suspend_for_pollable(pollable)

  // Finish connect
  let (input, output) = match socket.finish_connect() {
    Ok(streams) => streams
    Err(e) => {
      socket.drop()
      network.drop()
      raise SocketError::NetworkError(e)
    }
  }

  network.drop()
  TcpStream::{ socket, input, output }
}

///|
/// Read data from the TCP stream.
pub async fn TcpStream::read(self : TcpStream, max_len : Int) -> Bytes {
  let pollable = self.input.subscribe()
  @ev.suspend_for_pollable(pollable)

  match self.input.read(max_len.to_int64().reinterpret_as_uint64()) {
    Ok(data) => Bytes::from_array(data)
    Err(@streams.StreamError::Closed) => Bytes::make(0, b'\x00')
    Err(_) => raise SocketError::StreamError
  }
}

///|
/// Write data to the TCP stream.
pub async fn TcpStream::write(self : TcpStream, data : Bytes) -> Int {
  let mut offset = 0
  while offset < data.length() {
    let pollable = self.output.subscribe()
    @ev.suspend_for_pollable(pollable)
    let can_write = self.output.check_write().unwrap().to_int()
    if can_write > 0 {
      let chunk_size = @cmp.minimum(can_write, data.length() - offset)
      let chunk = FixedArray::makei(chunk_size, fn(i) { data[offset + i] })
      self.output.write(chunk).unwrap()
      offset += chunk_size
    }
  }
  self.output.flush().unwrap()
  let pollable = self.output.subscribe()
  @ev.suspend_for_pollable(pollable)
  data.length()
}

///|
/// Close the TCP stream.
pub fn TcpStream::close(self : TcpStream) -> Unit {
  self.input.drop()
  self.output.drop()
  self.socket.drop()
}

///|
/// Resolve a hostname to IP addresses.
pub async fn resolve(hostname : String) -> Array[IpAddr] {
  let network = @instanceNetwork.instance_network()

  let stream = match @ipNameLookup.resolve_addresses(network, hostname) {
    Ok(s) => s
    Err(e) => {
      network.drop()
      raise SocketError::NetworkError(e)
    }
  }

  let addresses : Array[IpAddr] = []

  while true {
    let pollable = stream.subscribe()
    @ev.suspend_for_pollable(pollable)

    match stream.resolve_next_address() {
      Ok(Some(addr)) => {
        let ip_addr = match addr {
          Ipv4((a, b, c, d)) => IpAddr::V4(Ipv4Addr::{ a, b, c, d })
          Ipv6(segments) => IpAddr::V6(Ipv6Addr::{ segments })
        }
        addresses.push(ip_addr)
      }
      Ok(None) => break
      Err(@wasiNetwork.ErrorCode::WOULD_BLOCK) => continue
      Err(e) => {
        stream.drop()
        network.drop()
        raise SocketError::NetworkError(e)
      }
    }
  }

  stream.drop()
  network.drop()
  addresses
}

///|
/// Parse an IPv4 address string.
pub fn parse_ipv4(s : String) -> Ipv4Addr? {
  let chars = s.to_array()
  let parts : Array[Int] = []
  let mut current = 0

  for i = 0; i <= chars.length(); i = i + 1 {
    if i == chars.length() || chars[i] == '.' {
      if current > 255 {
        return None
      }
      parts.push(current)
      current = 0
    } else {
      let c = chars[i]
      if c >= '0' && c <= '9' {
        current = current * 10 + (c.to_int() - '0'.to_int())
      } else {
        return None
      }
    }
  }

  if parts.length() != 4 {
    return None
  }

  Some(Ipv4Addr::{
    a: parts[0].to_byte(),
    b: parts[1].to_byte(),
    c: parts[2].to_byte(),
    d: parts[3].to_byte(),
  })
}
