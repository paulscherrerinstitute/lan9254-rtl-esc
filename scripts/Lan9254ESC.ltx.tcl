set ila_name hw_ila_3
if { [ info exists ::user_ila_name ] } {
  set ila_name $::user_ila_name
}

 create_hw_probe -map {probe0[13:0]} ESC.reqLoc.addr[13:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe0[15:14]} ESC.rxMBXDebug[1:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe0[20:16]} ESC.r.state[4:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe0[21]} ESC.reqLoc.rdnwr  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe0[22]} ESC.reqLoc.valid  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe0[23]} ESC.rep.valid  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe0[31:24]} ESC.testDbg[7:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe0[63:32]} ESC.reqLoc.data[31:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe1[31:0]} ESC.rep.rdata[31:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe1[63:32]} ESC.r.lastAL[31:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[2:0]} ESC.r.program.idx[2:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[3]} ESC.r.program.don  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[6:4]} ESC.r.program.num[2:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[7]} ESC.irq  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[8]} ESC.r.program.seq0.rdnwr  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[9]} ESC.r.program.seq1.rdnwr  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[10]} ESC.r.program.seq2.rdnwr  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[11]} ESC.stalled_or_rst [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[15:12]} ESC.r.program.seq0.reg.bena[3:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[19:16]} ESC.r.program.seq1.reg.bena[3:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[23:20]} ESC.r.program.seq2.reg.bena[3:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[27:24]} ESC.reqLoc.be[3:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[30:28]} ESC.rHBIMux.hbiState[2:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[31]} rxMBXDebug63_0  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe2[63:32]} ESC.r.program.seq0.val[31:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe3[31:0]} ESC.r.program.seq1.val[31:0]  [get_hw_ilas ${ila_name}]
 create_hw_probe -map {probe3[63:32]} ESC.r.program.seq2.val[31:0]  [get_hw_ilas ${ila_name}]
