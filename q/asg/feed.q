/ q asg/feed.q

system"l asg/util.q"

while[null tp: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni]];

.z.pc:{if[x = tp; while[null h: @[{hopen (`$":", .u.x: x; 5000)}; .z.x 0; 0Ni]]; `tp set h]};

i: tp `.u.i;
j: 0;
n: 1000;

hrs: `time$00:00    07:00    08:00      09:00       10:00        11:00        12:00        13:00      14:00        15:00       16:00;
intervals: $[.util.isAws;
                01:00:00 00:00:01 00:00:00:5 00:00:00:15 00:00:00:115 00:00:00:115 00:00:00:115 00:00:00:1 00:00:00:115 00:00:00:25 01:00:00;
                count[hrs]#00:00:01];

lgTime: .z.p;
pubTime:.z.p;

.z.ts:{[]
    .util.hb[];

    if[.z.p > lgTime + 00:01;
            .util.lg "Sending batch every ",string intervals hrs bin .z.t;
            show sum each .z.W;
            `lgTime set .z.p
            ];

    if[.z.p > pubTime + intervals hrs bin .z.t;
            fdata: `float$data:  105 - n?10;
            neg[tp] @ (`.u.upd;`Quote;(n#.z.p;n?`APPL`N`GM`GOOGL`INTC`JP`MSFT;fdata;fdata;data;data));
            neg[tp] @ (`.u.upd;`Trade;(n#.z.p;n?`APPL`N`GM`GOOGL`INTC`JP`MSFT;fdata;data));
            i+:2; j+:n;
            `pubTime set .z.p;
            ];
 };

system "t 50"
