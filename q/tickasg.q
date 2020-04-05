/ q tick-asg.q sym . -p 5001 </dev/null >foo 2>&1 &

/ launch kdb-tick
system "l tick.q"

/ load  .u.asg code
/ rewrites .u.sub & .u.add to take .z.w as a parameter
system "l asg/u-asg.q"

/ rewrite .z.pc to run tick and asg .z.pc
.tick.zpc: .z.pc;
.z.pc: {.tick.zpc x; .u.asg.zpc x;};

/ rewrite .u.end to run tick and asg .z.pc
.tick.end: .u.end;
.u.end: {.tick.end x; .u.asg.end x;};

/run
>q tick-asg.q sym  . -p 5010            /tick-asg
>q asg/r-asg.q $TICKHOST:5010 -p 5011   /rdb-asg
>q asg/feed.q  /feed
