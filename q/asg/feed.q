tp: hopen "::5010";

i: tp `.u.i;
j: 0;
n: 100;

.z.ts:{[]
    .util.hb[];

    fdata: `float$data: j + til n;
    neg[tp] @ (`.u.upd;`Quote;(n#.z.p;n?`APPL`C`GM`GOOGL`INTC`JP`MSFT;fdata;fdata;data;data));
    neg[tp] @ (`.u.upd;`Trade;(n#.z.p;n?`APPL`C`GM`GOOGL`INTC`JP`MSFT;fdata;data));
    i+:2; j+:n;
 };

system "t 100"
