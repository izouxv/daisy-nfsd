package nfsd

import (
	dirfs "github.com/mit-pdos/dafny-nfsd/dafnygen/DirFs_Compile"
	"github.com/mit-pdos/go-nfsd/nfstypes"

	"log"
)

func (nfs *Nfs) MOUNTPROC3_NULL() {
}

func (nfs *Nfs) MOUNTPROC3_MNT(args nfstypes.Dirpath3) nfstypes.Mountres3 {
	reply := new(nfstypes.Mountres3)
	log.Printf("Mount %v\n", args)
	reply.Fhs_status = nfstypes.MNT3_OK
	rootfh := Fh{Ino: dirfs.Companion_DirFilesys_.RootIno()}
	reply.Mountinfo.Fhandle = rootfh.MakeFh3().Data
	return *reply
}

func (nfs *Nfs) MOUNTPROC3_UMNT(args nfstypes.Dirpath3) {
	log.Printf("Unmount %v\n", args)
}

func (nfs *Nfs) MOUNTPROC3_UMNTALL() {
	log.Printf("Unmountall\n")
}

func (nfs *Nfs) MOUNTPROC3_DUMP() nfstypes.Mountopt3 {
	log.Printf("Dump\n")
	return nfstypes.Mountopt3{P: nil}
}

func (nfs *Nfs) MOUNTPROC3_EXPORT() nfstypes.Exportsopt3 {
	res := nfstypes.Exports3{
		Ex_dir:    "",
		Ex_groups: nil,
		Ex_next:   nil,
	}
	res.Ex_dir = "/"
	return nfstypes.Exportsopt3{P: &res}
}
