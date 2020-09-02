// asg/sub.q

/ called by the tickerplant when it begins publishing to the process
/ schemas   - table names and schemas of subscription tables
/ tplog     - file path of the tickerplant log
/ logWindow - start and end of the window needed in the log, (start;end)
.sub.rep:{[schemas;tplog;logWindow]
    .sub.live: 1b;
    (.[;();:;].) each schemas;
    .sub.start: logWindow 0;
    `upd set .sub.replayUpd;
    -11!(logWindow 1;tplog);
    `upd set .sub.upd;
    .z.ts: .sub.monitorMemory;
    system "t 5000";
 };

/ upd wrapper
/ only adds data from log window
/ monitors memory every 100 messages
.sub.replayUpd:{[t;data]
    if[.sub.i > .sub.start;
        if[not .sub.i mod 100; .sub.monitorMemory[]];
        .sub.upd[t;flip data];
        :(::);
        ];
    .sub.i+: 1;
 };

/ regular upd function
/ must keep track of upd message count
.sub.upd: {.sub.i+: 1; x upsert y; };

/ monitor server memory
/ check if the process needs to unsubscribe
.sub.monitorMemory:{[]
    if[.sub.live;
        if[.util.getMemUsage[] > .sub.rollThreshold;
                .sub.roll[];
                ];
        ];
 };

/ send tickerplant last upd message processed and unsubscribe
.sub.roll:{[]
    .sub.live: 0b;
    `upd set {[x;y] (::)};
    neg[.sub.TP] @ ({.u.asg.roll[.z.w;x]}; .sub.i);
 };

.sub.end:{[dt]
    .sub.i: 0;
    .sub.clear dt+1;
 };

/ clear data from all tables from before a certain time
/ terminate the the server if no data is left and the process is not live
/ tm - clear all data from all tables before this time
.sub.clear:{[tm]
    ![;enlist(<;`time;tm);0b;`$()] each tables[];
    if[.sub.live;
            .Q.gc[];
            neg[.sub.MON] (set;`.mon.scaled;0b);
            :(::);
            ];
    if[not max 0, count each get each tables[];
            .util.aws.terminate .aws.instanceId];
 };
