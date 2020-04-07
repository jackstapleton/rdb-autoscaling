/ q tickasg.q sym . -p 5001 </dev/null >foo 2>&1 &

/ launch kdb-tick and load .u.asg code
system "l tick.q"
system "l asg/u-asg.q"

/ rewrite .z.pc to run tick and asg .z.pc
.tick.zpc: .z.pc;
.z.pc: {.tick.zpc x; .u.asg.zpc x;};

/ rewrite .u.end to run tick and asg .z.pc
.tick.end: .u.end;
.u.end: {.tick.end x; .u.asg.end x;};

system "l asg/util.q"
.tick.ts: .z.ts;
.z.ts:{[]
    .tick.ts;
    .util.hb;
    .util.lgAsgInfo[];
 };
system "t 200";
