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
test "parse_ipv4 valid" {
  let addr = parse_ipv4("192.168.1.1")
  assert_true(addr is Some(_))
  let addr = addr.unwrap()
  assert_eq(addr.a, b'\xc0') // 192
  assert_eq(addr.b, b'\xa8') // 168
  assert_eq(addr.c, b'\x01') // 1
  assert_eq(addr.d, b'\x01') // 1
}

///|
test "parse_ipv4 localhost" {
  let addr = parse_ipv4("127.0.0.1")
  assert_true(addr is Some(_))
  let addr = addr.unwrap()
  assert_eq(addr.a, b'\x7f') // 127
  assert_eq(addr.b, b'\x00') // 0
  assert_eq(addr.c, b'\x00') // 0
  assert_eq(addr.d, b'\x01') // 1
}

///|
test "parse_ipv4 zeros" {
  let addr = parse_ipv4("0.0.0.0")
  assert_true(addr is Some(_))
  let addr = addr.unwrap()
  assert_eq(addr.a, b'\x00')
  assert_eq(addr.b, b'\x00')
  assert_eq(addr.c, b'\x00')
  assert_eq(addr.d, b'\x00')
}

///|
test "parse_ipv4 max values" {
  let addr = parse_ipv4("255.255.255.255")
  assert_true(addr is Some(_))
  let addr = addr.unwrap()
  assert_eq(addr.a, b'\xff')
  assert_eq(addr.b, b'\xff')
  assert_eq(addr.c, b'\xff')
  assert_eq(addr.d, b'\xff')
}

///|
test "parse_ipv4 invalid - too few parts" {
  let addr = parse_ipv4("192.168.1")
  assert_true(addr is None)
}

///|
test "parse_ipv4 invalid - too many parts" {
  let addr = parse_ipv4("192.168.1.1.1")
  assert_true(addr is None)
}

///|
test "parse_ipv4 invalid - value too large" {
  let addr = parse_ipv4("256.0.0.0")
  assert_true(addr is None)
}

///|
test "parse_ipv4 invalid - non-numeric" {
  let addr = parse_ipv4("abc.0.0.0")
  assert_true(addr is None)
}

///|
test "parse_ipv4 empty string" {
  let addr = parse_ipv4("")
  assert_true(addr is None)
}
