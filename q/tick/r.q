/q tick/r.q [host]:port[:usr:pwd] [host]:port[:usr:pwd]
/2008.09.09 .k ->.q

system "l asg/util.q";

/ kx dashboards set up
system "l tick/u.q";
system "x .z.pc";
.u.snap:{select from x[0]};

if[not "w"=first string .z.o;system "sleep 1"];

upd:{[t;x] if[t~`MemUsage;t insert x]}

/ get the ticker plant and history ports, defaults are 5010,5012
.u.x:.z.x,(count .z.x)_(":5010";":5012");

/ end of day: save, clear, hdb reload
.u.end:{t:tables`.;t@:where `g=attr each t@\:`sym;.Q.hdpf[`$":",.u.x 1;`:.;x;`sym];@[;`sym;`g#] each t;};
.u.end:{t:tables`.;![;enlist(<;`time;x);0b;`$()]each t;@[;`sym;`g#]each t;}

/ init schema and sync up from log file;cd to hdb(so client save can run)
.u.rep:{(.[;();:;].) x;if[null first y;:()];-11!y;system "cd ",1_-10_string first reverse y};
/ HARDCODE \cd if other than logdir/db

/ connect to ticker plant for (schema;(logcount;log))
.u.rep .(hopen `$":",.u.x 0)"(.u.sub[`MemUsage;`];`.u `i`L)";

.u.snap:{[x] select from x[0]}
.util.name:`rdb;
.z.ts: .util.hb;
system "t 200";
