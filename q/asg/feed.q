
system"l asg/util.q"

tp: hopen "::5010";

i: tp `.u.i;
j: 0;
n: 500;

hrs: `time$07:00 08:00 09:00 10:00 11:00 12:00 13:00 14:00 15:00 16:00;
factors:   .08   .2    .72   .91  .94   .92    1     .91   .37   0;

.z.ts:{[]
    .util.hb[];

    if[0 < N: `int$ n * 0f^ factors hrs bin .z.t;
            fdata: `float$data: j + til N;
            neg[tp] @ (`.u.upd;`Quote;(N#.z.p;N?`APPL`N`GM`GOOGL`INTC`JP`MSFT;fdata;fdata;data;data));
            neg[tp] @ (`.u.upd;`Trade;(N#.z.p;N?`APPL`N`GM`GOOGL`INTC`JP`MSFT;fdata;data));
            i+:2; j+:N;
            ];
 };

system "t 100"
