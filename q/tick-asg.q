/ q tick-asg.q sym . -p 5001 </dev/null >foo 2>&1 &

/ launch kdb-tick
system "l tick.q"

/ rewrite .u.sub & .u.add to take .z.w as a parameter
/ load  .u.asg code
system "l asg/u-asg.q"

/ rewrite .z.pc to run tick and asg .z.pc
.tick.zpc: .z.pc;
.z.pc: {.u.asg.zpc x; .tick.zpc x};

/ rewrite .u.end to run tick and asg .z.pc
.tick.end: .u.end;
.u.end: {.tick.end x; .u.asg.end x};
