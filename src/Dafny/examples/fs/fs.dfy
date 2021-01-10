include "../../util/marshal.i.dfy"
include "../../jrnl/jrnl.s.dfy"

// NOTE: this module, unlike the others in this development, is not intended to
// be opened
//
// NOTE: factoring out Inode to a separate file made this file much _slower_ for
// some reason
module Inode {
  import opened Machine
  import IntEncoding
  import opened Collections
  import opened ByteSlice
  import opened Marshal

  datatype Inode = Mk(sz: uint64, blks: seq<uint64>)

  function method div_roundup(x: nat, k: nat): nat
    requires k >= 1
  {
    (x + (k-1)) / k
  }

  function method NextBlock(i:Inode): uint64
  {
    i.sz/4096
  }

  predicate Valid(i:Inode)
  {
    var blks_ := i.blks;
    // only direct blocks
    && |blks_| == 15
    && i.sz as nat/4096 <= 15
    // TODO: generalize to allow non-block appends
    && i.sz % 4096 == 0
    && unique(blks_[..NextBlock(i) as nat])
  }


  function inode_enc(i: Inode): seq<Encodable>
  {
    [EncUInt64(i.sz)] + seq_fmap(blkno => EncUInt64(blkno), i.blks)
  }

  function enc(i: Inode): seq<byte>
  {
    seq_encode(inode_enc(i))
  }

  const zero: Inode := Mk(0, repeat(0 as uint64, 15));

  lemma zero_valid()
    ensures Valid(zero)
  {}

  lemma {:induction count} repeat_zero_ints(count: nat)
    ensures seq_encode(repeat(EncUInt64(0), count)) == repeat(0 as byte, 8*count)
  {
    var z := EncUInt64(0);
    if count == 0 {
      reveal_repeat();
      assert 8*count == 0;
      assert repeat(z, count) == [];
      //assert seq_encode([]) == [];
      assert repeat(0 as byte, 8*count) == [];
    } else {
      IntEncoding.lemma_enc_0();
      assert repeat(0 as byte, 8) == enc_encode(z);
      repeat_split(0 as byte, 8*count, 8, 8*(count-1));
      repeat_zero_ints(count-1);
      assert repeat(z, count) == [z] + repeat(z, count-1);
      //assert seq_encode(repeat(z, count)) == repeat(0 as byte, 8) + repeat(0 as byte, 8*(count-1));
      //assert seq_encode([z]) == repeat(0 as byte, 8);
    }
  }

  lemma zero_encoding()
    ensures Valid(zero)
    ensures repeat(0 as byte, 128) == enc(zero)
  {
    zero_valid();
    assert inode_enc(zero) == [EncUInt64(0)] + repeat(EncUInt64(0), 15);
    assert inode_enc(zero) == repeat(EncUInt64(0), 16);
    repeat_zero_ints(16);
  }

  method encode_ino(i: Inode) returns (bs:Bytes)
    modifies {}
    requires Valid(i)
    ensures fresh(bs)
    ensures bs.data == enc(i)
    ensures |bs.data| == 128
  {
    var e := new Encoder(128);
    e.PutInt(i.sz);
    var k: nat := 0;
    while k < 15
      modifies e.Repr
      invariant e.Valid()
      invariant 0 <= k <= 15
      invariant e.bytes_left() == 128 - ((k+1)*8)
      invariant e.enc ==
      [EncUInt64(i.sz)] +
      seq_fmap(blkno => EncUInt64(blkno), i.blks[..k])
    {
      e.PutInt(i.blks[k]);
      k := k + 1;
    }
    assert i.blks[..15] == i.blks;
    assert e.enc == inode_enc(i);
    bs := e.FinishComplete();
  }

  method decode_ino(bs: Bytes, ghost i: Inode) returns (i': Inode)
    modifies {}
    requires bs.Valid()
    requires Valid(i)
    requires bs.data == enc(i)
    ensures i' == i
  {
    var dec := new Decoder();
    dec.Init(bs, inode_enc(i));
    var sz := dec.GetInt(i.sz);
    assert dec.enc == seq_fmap(blkno => EncUInt64(blkno), i.blks);

    var blks: seq<uint64> := [];

    var k: nat := 0;
    while k < 15
      modifies dec
      invariant dec.Valid()
      invariant Valid(i)
      invariant 0 <= k <= 15
      invariant blks == i.blks[..k]
      invariant dec.enc == seq_fmap(blkno => EncUInt64(blkno), i.blks[k..])
    {
      var blk := dec.GetInt(i.blks[k]);
      blks := blks + [blk];
      k := k + 1;
    }
    return Mk(sz, blks);
  }
}

module Fs {
  import Inode
  import opened Machine
  import opened ByteSlice
  import opened JrnlSpec
  import opened Kinds
  import opened Marshal

  type Ino = uint64

  predicate blkno_ok(blkno: Blkno) { blkno < 4096*8 }
  predicate ino_ok(ino: Blkno) { ino < 32 }

  // disk layout, in blocks:
  //
  // 513 for the jrnl
  // 1 inode block (32 inodes)
  // 1 bitmap block
  // 4096*8 data blocks
  const NumBlocks: nat := 513 + 1 + 1 + 4096*8
    // if you want to make a disk for the fs 40,000 blocks is a usable number
  lemma NumBlocks_upper_bound()
    ensures NumBlocks < 40_000
  {}

  const InodeBlk: Blkno := 513
  const DataAllocBlk: Blkno := 514

  function method InodeAddr(ino: Ino): (a:Addr)
    requires ino_ok(ino)
    ensures a in addrsForKinds(fs_kinds)
  {
    kind_inode_size();
    assert fs_kinds[InodeBlk] == KindInode;
    Addr(InodeBlk, ino*128*8)
  }
  function method DataBitAddr(bn: uint64): Addr
    requires blkno_ok(bn)
  {
    Addr(DataAllocBlk, bn)
  }
  function method DataBlk(bn: uint64): Addr
    requires blkno_ok(bn)
  {
    Addr(513+2+bn, 0)
  }

  const fs_kinds: map<Blkno, Kind> :=
    // NOTE(tej): trigger annotation suppresses warning (there's nothing to
    // trigger on here, but also nothing is necessary)
    map blkno: Blkno {:trigger} |
      513 <= blkno as nat < NumBlocks
      :: (if blkno == InodeBlk
      then KindInode
      else if blkno == DataAllocBlk
        then KindBit
        else KindBlock) as Kind

  lemma fs_kinds_valid()
    ensures kindsValid(fs_kinds)
  {}

  datatype Option<T> = Some(x:T) | None

  class Filesys
  {

    // spec state
    ghost var data: map<Ino, seq<byte>>;

    // intermediate abstractions
    ghost var inodes: map<Ino, Inode.Inode>;
    // gives the inode that owns the block
    ghost var block_used: map<Blkno, Option<Ino>>;
    ghost var data_block: map<Blkno, seq<byte>>;

    var jrnl: Jrnl;
    var balloc: Allocator;

    predicate Valid_basics()
      reads this, jrnl
    {
      && jrnl.Valid()
      && jrnl.kinds == fs_kinds
    }

    static lemma blkno_bit_inbounds(jrnl: Jrnl)
      requires jrnl.Valid()
      requires jrnl.kinds == fs_kinds
      ensures forall bn :: blkno_ok(bn) ==> DataBitAddr(bn) in jrnl.data
    {}

    static lemma inode_inbounds(jrnl: Jrnl)
      requires jrnl.Valid()
      requires jrnl.kinds == fs_kinds
      ensures forall ino :: ino_ok(ino) ==> InodeAddr(ino) in jrnl.data
    {
      kind_inode_size();
      forall ino : Ino | ino_ok(ino)
        ensures InodeAddr(ino).blkno == InodeBlk
      {
      }
    }

    predicate Valid_block_used()
      requires Valid_basics()
      reads this, jrnl
    {
      blkno_bit_inbounds(jrnl);
      && (forall bn :: blkno_ok(bn) ==> bn in block_used)
      && (forall bn | bn in block_used ::
        && blkno_ok(bn)
        && jrnl.data[DataBitAddr(bn)] == ObjBit(block_used[bn].Some?))
    }

    predicate Valid_data_block()
      requires Valid_basics()
      reads this, jrnl
    {
      && (forall bn :: blkno_ok(bn) ==> bn in data_block)
      && (forall bn | bn in data_block ::
        && blkno_ok(bn)
        && jrnl.data[DataBlk(bn)] == ObjData(data_block[bn]))
    }

    predicate Valid_inodes()
      requires Valid_basics()
      reads this, jrnl
    {
      inode_inbounds(jrnl);
      && (forall ino: Ino | ino_ok(ino) :: ino in inodes)
      && (forall ino: Ino | ino in inodes ::
        var i := inodes[ino];
        && ino_ok(ino)
        && Inode.Valid(i)
        && jrnl.data[InodeAddr(ino)] == ObjData(Inode.enc(i))
        && (forall bn | bn in i.blks && bn != 0 ::
          && bn in block_used
          && block_used[bn] == Some(ino))
        )
    }

    predicate Valid_data()
      requires Valid_basics()
      requires Valid_inodes()
      reads this, jrnl
    {
      inode_inbounds(jrnl);
      && (forall ino: Ino | ino in data :: ino in inodes)
      && (forall ino: Ino | ino in inodes ::
         var i := inodes[ino];
         && ino in data
         && i.sz as nat == |data[ino]|
         && (forall k: nat | k < |data[ino]|/4096 ::
           && i.blks[k] in data_block
           && data[ino][k * 4096..(k+1)*4096] == data_block[i.blks[k]])
         )
    }

    predicate Valid()
      reads this, balloc, jrnl
    {
      // TODO: split this into multiple predicates, ideally opaque
      && Valid_basics()

      && this.Valid_block_used()
      && this.Valid_data_block()
      && this.Valid_inodes()
      // && this.Valid_data()

      // TODO: tie inode ownership to inode block lists
      && this.balloc.max == 4095*8
      && this.balloc.Valid()
    }

    constructor(d: Disk)
      ensures Valid()
    {
      var jrnl := NewJrnl(d, fs_kinds);
      this.jrnl := jrnl;
      var balloc := NewAllocator(4095*8);
      this.balloc := balloc;

      this.data := map ino: Ino | ino_ok(ino) :: [];
      this.inodes := map ino: Ino | ino_ok(ino) :: Inode.zero;
      Inode.zero_encoding();
      this.block_used := map bn: uint64 |
        blkno_ok(bn) :: None;
      this.data_block := map bn: uint64 |
        blkno_ok(bn) :: zeroObject(KindBlock).bs;
      new;
      assert Valid_inodes();
    }

    // full block append
    static predicate can_inode_append(i: Inode.Inode, bn: Blkno)
    {
      && Inode.Valid(i)
      && blkno_ok(bn)
      && i.sz < 15*4096
    }

    static function method inode_append(i: Inode.Inode, bn: Blkno): (i':Inode.Inode)
    requires can_inode_append(i, bn)
    {
      Inode.Mk(i.sz + 4096, i.blks[Inode.NextBlock(i) as nat:=bn])
    }

    method Alloc(txn: Txn) returns (ok:bool, bn:Blkno)
      modifies balloc
      requires txn.jrnl == this.jrnl
      requires Valid() ensures Valid()
      ensures ok ==>
        (&& bn != 0
        && bn-1 < 4095*8
        && block_used[bn].None?
        )
    {
      bn := balloc.Alloc(); bn := bn + 1;
      var used := txn.ReadBit(DataBitAddr(bn));
      if used {
        ok := false;
        balloc.Free(bn-1);
        return;
      }
      ok := true;
    }

    lemma free_block_unused(bn: Blkno)
      requires Valid()
      requires blkno_ok(bn) && bn != 0 && block_used[bn].None?
      ensures forall ino | ino_ok(ino) :: bn !in inodes[ino].blks
    {}

    method Append(ino: Ino, bs: Bytes) returns (ok:bool, ghost alloc_bn: Option<Blkno>)
      modifies this, jrnl, balloc
      requires Valid() ensures Valid()
      requires ino_ok(ino)
      requires |bs.data| == 4096
      ensures ok ==>
        && alloc_bn.Some?
        && alloc_bn.x in old(block_used)
        && old(block_used[alloc_bn.x]).None?
        && block_used == old(block_used[alloc_bn.x:=Some(ino)])
        && data_block == old(data_block[alloc_bn.x:=bs.data])
        && can_inode_append(old(inodes[ino]), alloc_bn.x)
        && inodes == old(inodes[ino:=inode_append(inodes[ino], alloc_bn.x)])
    {
      alloc_bn := None;

      var txn := jrnl.Begin();

      // allocate and validate
      var alloc_ok, bn := Alloc(txn);
      if !alloc_ok {
        ok := false;
        return;
      }
      free_block_unused(bn);

      // mark bn in-use now
      block_used := block_used[bn:=Some(ino)];
      txn.WriteBit(DataBitAddr(bn), true);

      var buf := txn.Read(InodeAddr(ino), 128*8);
      var i := Inode.decode_ino(buf, inodes[ino]);
      if i.sz == 15*4096 {
        ok := false;
        balloc.Free(bn-1);
        return;
      }
      var i' := inode_append(i, bn);
      assert i'.blks[..Inode.NextBlock(i')] == i.blks[..Inode.NextBlock(i)] + [bn];
      Collections.unique_extend(i.blks[..Inode.NextBlock(i)], bn);
      assert Inode.Valid(i');
      i := i';
      var buf' := Inode.encode_ino(i);
      txn.Write(InodeAddr(ino), buf');
      inodes := inodes[ino:=i];

      txn.Write(DataBlk(bn), bs);
      data_block := data_block[bn:=bs.data];

      // data := data[ino:=data[ino] + bs.data];

      ok := true;
      alloc_bn := Some(bn);

      var _ := txn.Commit();
    }

    method Size(ino: Ino) returns (sz: uint64)
      requires Valid() ensures Valid()
      requires ino_ok(ino)
      ensures sz == inodes[ino].sz
    {
      var txn := jrnl.Begin();
      kind_inode_size();
      var buf := txn.Read(InodeAddr(ino), 128*8);
      var i := Inode.decode_ino(buf, inodes[ino]);
      sz := i.sz;
      var _ := txn.Commit();
    }

    method Get(ino: Ino, off: uint64, len: uint64)
      returns (ok:bool, data: Bytes)
      modifies {}
      requires off % 4096 == 0 && len == 4096
      requires ino_ok(ino)
      requires Valid() ensures Valid()
      ensures ok ==> fresh(data)
    {
      var txn := jrnl.Begin();
      kind_inode_size();
      var buf := txn.Read(InodeAddr(ino), 128*8);
      var i := Inode.decode_ino(buf, inodes[ino]);
      if sum_overflows(off, len) || off+len >= i.sz {
        ok := false;
        data := NewBytes(0);
        return;
      }
      ok := true;
      var blk := i.blks[off / 4096];
      data := txn.Read(DataBlk(blk), 4096*8);
      var _ := txn.Commit();
    }
  }
}
