
/ .u.add and .u.sub changed to take handle as a 3rd argument instead of using .z.w
\d .u

/ use 'z' instead of .z.w
add:{$[(count w x)>i:w[x;;0]?z;.[`.u.w;(x;i;1);union;y];w[x],:enlist(z;y)];(x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])}

/ use 'z' instead of .z.w, and input as 3rd argument to .u.add
subInner:{if[x~`;:sub[;y]each t];if[not x in t;'x];del[x]z;add[x;y;z]}
sub:{subInner[x;y;.z.w]}

\d .

/ table used to handle subscriptions
/   time   - time the subscriber was added
/   handle - handle of the subscriber
/   tabs   - tables the subscriber has subscribed for
/   syms   - syms the subscriber has subscribed for
/   queue  - queue the subscriber is a part of
/   live   - whether the subscriber is currently being published to
/   rolled - whether the subscriber has cut its subscription
/   lastI  - last message sent to the subscriber

.u.asg.tab: flip `time`handle`tabs`syms`queue`live`rolled`lastI!();
`.u.asg.tab upsert (0Np;0Ni;();();`;0b;0b;0N);

.u.asg.sub:{[t;s;q]
    -1 "New process subscribing: on handle ",string .z.w;

    if[not (=) . count each (t;s);
            '"Count of table and symbol lists must match" ];

    if[not all missing: t in .u.t,`;
            '.Q.s1[t where not missing]," not available" ];

    / add new process to subscriber table
    `.u.asg.tab upsert (.z.p; .z.w; t; s; q; 0b; 0b; 0N);

    / check if there is a live subscriber
    / start publishing to the handle if there is not
    if[not count select from .u.asg.tab where live, queue = q;
            .u.asg.add[t;s;.z.w] ];

    .u.asg.showInfo[];
 };

.u.asg.add:{[t;s;h]
    / mark this handle as the live subscriber
    update live:1b from `.u.asg.tab where handle = h;

    / add subscriber to .u.w
    schemas: $[-11h = type t;
                    enlist .u.subInner[t;s;h];
                    .u.subInner[;;h] .' flip (t;s)];

    / find the last message sent to a subscriber
    startI: max 0^ exec lastI from .u.asg.tab;

    / tell the new subscriber to replay tickerplant log from that message
    neg[h] (`.sub.rep; schemas; .u.L; (startI;.u.i));
 };

.u.asg.roll:{[h;subI]
    -1 "Subscriber on handle as ",(string h)," has stopped subscribing";
    cfg: exec from .u.asg.tab where handle = h;

    / mark process as rolled
    update live:0b, rolled:1b, lastI:subI from `.u.asg.tab where handle = h;

    / delete handle from .u.w
    .u.del[;h] each cfg`tabs;

    / find the next subscriber for the same tables and syms
    queue: select from .u.asg.tab where not live, not rolled, queue = cfg`queue;

    if[not count queue;
        :-1 "No process in the subscriber queue" ];

    / start publishing to the first process in the queue
    .u.asg.add . first[queue]`tabs`syms`handle;

    .u.asg.showInfo[];
 };

.u.asg.end:{[]
    -1  "Clearing data from rolled ASG subscribers";
    rolled: exec handle from .u.asg.tab where not null handle, rolled, not live;
    rolled @\: (`.u.end; .u.d);
    delete from `.u.asg.tab where rolled;

    .u.asg.showInfo[];
 };

.u.asg.zpc:{[h]
    / roll subscriber with 0 completed upd msgs if connection to the live subscriber is lost
    if[0b^ first exec live from .u.asg.tab where handle = h;
            .u.asg.roll[h;0] ];

    update handle:0Ni from `.u.asg.tab where handle = h;
 };

.u.asg.showInfo:{[]
    if[n:count .u.asg.tab;
            -1  string[n]," subscribers connected from Autoscaling Groups";
            show .u.asg.tab ];
 };
