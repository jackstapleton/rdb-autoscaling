/ q asg/feed.q

system"l asg/util.q"

while[null .feed.TP: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni]];

.feed.N:10000;

.z.pc:{[h]
    if[h = .feed.TP;
        .feed.TP:0Ni;
        while[null .feed.TP: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni]];
        ];
 };


.z.ts:{[]
    .util.hb[];
    fdata:`float$data:  105 - n?10;
    neg[.feed.TP] @ (`.u.upd;`Quote;(n?`APPL`N`GM`GOOGL`INTC`JP`MSFT;fdata;fdata;data;data));
    neg[.feed.TP] @ (`.u.upd;`Trade;(n?`APPL`N`GM`GOOGL`INTC`JP`MSFT;fdata;data));

 };

system "t 100"
