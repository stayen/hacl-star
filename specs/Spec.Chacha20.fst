module Spec.Chacha20
open FStar.Mul
open Spec.Lib.IntTypes
open Spec.Lib.IntSeq
open Spec.Lib.RawIntTypes

open Spec.Chacha20.Lemmas


#set-options "--max_fuel 0 --z3rlimit 100"

(* Constants *)
let keylen = 32   (* in bytes *)
let blocklen = 64 (* in bytes *)
let noncelen = 12 (* in bytes *)

type key = lbytes keylen
type block = lbytes blocklen
type nonce = lbytes noncelen
type counter = size_t

// Internally, blocks are represented as 16 x 4-byte integers
type state = m:intseq U32 16
type idx = n:size_t{n < 16}
type shuffle = state -> Tot state

// Using @ as a functional substitute for ;
let op_At f g = fun x -> g (f x)

let line (a:idx) (b:idx) (d:idx) (s:rotval U32) (m:state) : Tot state =
  let m = m.[a] <- (m.[a] +. m.[b]) in
  let m = m.[d] <- ((m.[d] ^. m.[a]) <<<. s) in m

let quarter_round a b c d : shuffle =
  line a b d (u32 16) @
  line c d b (u32 12) @
  line a b d (u32 8)  @
  line c d b (u32 7)

let column_round : shuffle =
  quarter_round 0 4 8  12 @
  quarter_round 1 5 9  13 @
  quarter_round 2 6 10 14 @
  quarter_round 3 7 11 15

let diagonal_round : shuffle =
  quarter_round 0 5 10 15 @
  quarter_round 1 6 11 12 @
  quarter_round 2 7 8  13 @
  quarter_round 3 4 9  14

let double_round : shuffle =
  column_round @ diagonal_round (* 2 rounds *)

let rounds : shuffle =
  repeat 10 double_round (* 20 rounds *)

let chacha20_core (s:state) : Tot state =
  let s' = rounds s in
  map2 (fun x y -> x +. y) s' s

(* state initialization *)
let c0 = 0x61707865
let c1 = 0x3320646e
let c2 = 0x79622d32
let c3 = 0x6b206574

let setup (k:key) (n:nonce) (c:counter) (st:state) : Tot state =
  let st = st.[0] <- u32 c0 in
  let st = st.[1] <- u32 c1 in
  let st = st.[2] <- u32 c2 in
  let st = st.[3] <- u32 c3 in
  let st = update_sub st 4 8 (uints_from_bytes_le k) in
  let st = st.[12] <- u32 c in
  let st = update_sub st 13 3 (uints_from_bytes_le n) in
  st

let chacha20_block (k:key) (n:nonce) (c:counter): Tot block =
  let st = create 16 (u32 0) in
  let st  = setup k n c st in
  let st' = chacha20_core st in
  uints_to_bytes_le st'

let chacha20_ctx: Spec.CTR.block_cipher_ctx =
  let open Spec.CTR in
  {
    keylen = keylen;
    blocklen = blocklen;
    noncelen = noncelen;
    countermax = 1
  }

let chacha20_cipher: Spec.CTR.block_cipher chacha20_ctx = chacha20_block

let chacha20_encrypt_bytes key nonce counter m =
    Spec.CTR.counter_mode chacha20_ctx chacha20_cipher key nonce counter m
