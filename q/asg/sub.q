// asg/sub.q

/ load code to scale and terminate instances from autoscaling group
system "l asg/util.q"

/ called by the tickerplant when it begins publishing to the process
.sub.rep:{[schemas;date;tplog;logWindow]
    -1 "Tickerplant called .sub.rep, process is now the live subscriber";

    (.[;();:;].) each schemas;

    .sub.live: 1b;
    .sub.d: date;
    .sub.start: logWindow 0;

    -1 "Replaying ", string tplog;
    -1 "Between ", .Q.s1 logWindow;
    `upd set .sub.replayUpd;
    -11!(logWindow 1;tplog);

    `upd set .sub.upd;
 };

/ wrapper to check memory during a replay
.sub.replayUpd:{[t;x]
    / run .sub.upd if .sub.i is greater than start
    if[.sub.i > .sub.start;
        .sub.monitorMemory[];
        .sub.upd[t;flip x];
        :(::);
        ];
    / increment .sub.i if .sub.upd is not run
    .sub.i+: 1;
 };

/ regular upd, must keep track of upd message count
/ tickerplant will use it to tell the next rdb where to start from
.sub.upd: {.sub.i+: 1; x upsert y };

/ monitor server memory to first check if a new server needs to be launched
/ and second check if the process needs to cut its subscription
.sub.monitorMemory:{[]
    / check if it is time to launch another rdb server
    if[not .sub.scaled;
        if[.sub.getMemUsage[] > .sub.scaleThreshold;
                -1 "Scaling ", .aws.groupName;
                .util.aws.scale .aws.groupName;
                .sub.scaled: 1b;
                ];
        :(::);
        ];
    / check if server is full and process needs to stop subscribing
    if[not .sub.rolled;
        if[.sub.getMemUsage[] > .sub.rollThreshold;
                .sub.cutSubscription[];
                .sub.rolled: 1b;
                ];
        ];
 };

.sub.getMemUsage:{[]
    mem: .util.getMemUsage[];
    -1 "Box is at ",string[mem],"% memory usage";
    mem
 };

/ send tickerplant last upd message recieeved and cut subscription
.sub.cutSubscription:{[]
    -1 "Cutting subscription";
    .sub.TP ({.u.asg.rollSubscriber[.z.w;x]}; .sub.i);
    .sub.live: 0b;
    .sub.rolled: 1b;
    `upd set .sub.disconnectUpd;
 };

/ upd to run after subscription has been cut
.sub.disconnectUpd: {[t;x] (::)};

/ clear data from all tables from before a certain time
/ terminate the the server if no data is left and the process has cut its subscription
.sub.clear:{[tm]
    -1 "Clearing data from before ",string[tm]," from ",.Q.s1 tables[];

    ![;enlist(<;`time;tm);0b;`$()] each tables[];

    if[.sub.rolled;
        -1 "Table counts after clearing:";
        show tabCounts: tables[]!count each get each tables[];

        if[not max value tabCounts;
            -1 "No data left in tables - terminating ", .aws.instanceId," from ",.aws.groupName;
            .util.aws.terminate .aws.instanceId;
            ];
        ];
 };
