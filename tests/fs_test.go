package compile_test

import (
	fs "github.com/mit-pdos/dafny-nfsd/dafnygen/ByteFs_Compile"
	"testing"

	"github.com/mit-pdos/dafny-nfsd/dafny_go/bytes"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/tchajed/goose/machine/disk"
)

func TestFsSanity_Block(t *testing.T) {
	assert := assert.New(t)
	var d disk.Disk = disk.NewMemDisk(100_000)
	filesys := fs.New_ByteFilesys_()
	filesys.Init(&d)
	ino := uint64(3)

	bs := bytes.Data(make([]byte, 4096))
	copy(bs.Data, []byte{1, 2, 3, 4})
	filesys.Append(ino, bs)
	filesys.Append(ino, bs)
	bs2, ok := filesys.Read(ino, 4096, 4096)
	assert.True(ok)
	assert.Equal(byte(1), bs2.Data[0])
}

func TestFsSanity(t *testing.T) {
	assert := assert.New(t)
	var d disk.Disk = disk.NewMemDisk(100_000)
	filesys := fs.New_ByteFilesys_()
	filesys.Init(&d)
	ino := uint64(3)

	bs := bytes.Data([]byte{1, 2, 3, 4})
	{
		ok := filesys.Append(ino, bs)
		require.True(t, ok, "aligned append should succeed")
	}
	assert.Equal(uint64(4), filesys.Size(ino))

	bs = bytes.Data([]byte{1, 2, 3, 4})
	{
		ok := filesys.Append(ino, bs)
		require.True(t, ok, "unaligned append should succeed")
	}
	assert.Equal(uint64(8), filesys.Size(ino))

	bs2 := bytes.Data(make([]byte, 4096))
	copy(bs2.Data[4096-8:], []byte{5, 6, 7, 8})

	// requires both writing to end of file and allocating
	filesys.Append(ino, bs2)

	{
		bs, ok := filesys.Read(ino, 0, 4)
		if assert.True(ok) {
			assert.Equal(byte(1), bs.Data[0])
		}
	}

	{
		bs, ok := filesys.Read(ino, 4096, 4)
		if assert.True(ok) {
			assert.Equal(byte(5), bs.Data[0])
		}
	}
}

func BenchmarkFsInit(b *testing.B) {
	var d disk.Disk = disk.NewMemDisk(100_000)
	filesys := fs.New_ByteFilesys_()
	b.ResetTimer()
	for b_iter := 0; b_iter < b.N; b_iter++ {
		filesys.Init(&d)
	}
}

func BenchmarkFsAppend100(b *testing.B) {
	var d disk.Disk = disk.NewMemDisk(100_000)
	filesys := fs.New_ByteFilesys_()
	b.ResetTimer()
	for b_iter := 0; b_iter < b.N; b_iter++ {
		filesys.Init(&d)
		// FIXME: technically Append owns its input; that should probably be
		// fixed somehow
		bs := bytes.Data(make([]byte, 4096))
		// every benchmark iteration we do 100 appends to a fresh filesystem
		for i := 0; i < 10; i++ {
			for ino := uint64(0); ino < 10; ino++ {
				filesys.Append(ino, bs)
			}
		}
	}
}
