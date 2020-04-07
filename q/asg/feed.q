
system"l asg/util.q"

tp: hopen "::5010";

i: tp `.u.i;
j: 0;
n: 500;

hrs: `time$07:00 08:00 09:00 10:00 11:00 12:00 13:00 14:00 15:00 16:00;
factors:   .08   .2    .72   .91  .94   .92    1     .91   .37   0;

.z.ts:{[]
    .util.hb[];

    if[count c: 0f^ factors hrs bin .z.t;
            fdata: `float$data: j + til c;
            neg[tp] @ (`.u.upd;`Quote;(c#.z.p;c?`APPL`C`GM`GOOGL`INTC`JP`MSFT;fdata;fdata;data;data));
            neg[tp] @ (`.u.upd;`Trade;(c#.z.p;c?`APPL`C`GM`GOOGL`INTC`JP`MSFT;fdata;data));
            i+:2; j+:c;
            ];
 };

system "t 100"
