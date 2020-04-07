// asg/u.q

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
/   live   - time the tickerplant addd the subscriber to .u.w
/   rolled - time the subscriber unsubscribed
/   lastI  - last message sent to the subscriber
.u.asg.tab: flip `time`handle`tabs`syms`queue`live`rolled`lastI!();
`.u.asg.tab upsert (0Np;0Ni;();();`;0Np;0Np;0N);

/ t - A list of tables (or \` for all).
/ s - Lists of symbol lists to subscribe to for the tables.
/ q - The name of the queue to be added to.
.u.asg.sub:{[t;s;q]
    .util.lg "Process subscribing to queue - ",string[q]," on handle ", string .z.w;

    if[-11h = type t;
            t: enlist t;
            s: enlist s];

    if[not (=) . count each (t;s);
            '"Count of table and symbol lists must match" ];

    if[not all missing: t in .u.t,`;
            '.Q.s1[t where not missing]," not available" ];

    `.u.asg.tab upsert (.z.p; .z.w; t; s; q; 0Np; 0Np; 0N);

    if[not count select from .u.asg.tab where null live, queue = q;
            .u.asg.add[.z.w;t;s]];

    show .u.asg.tab
 };

/ t - List of tables the RDB wants to subscribe to.
/ s - Symbol lists the RDB wants to subscribe to.
/ h - The handle of the RDB.
.u.asg.add:{[t;s;h]
    .util.lg "Adding process on handle ",string[h]," to .u.w";

    update live:.z.p from `.u.asg.tab where handle = h;
    schemas: .u.subInner[;;h] .' flip (t;s);
    neg[h] (`.sub.rep; schemas; .u.L; (max 0^ exec lastI from .u.asg.tab; .u.i));
 };

/ h    - handle of the RDB
/ subI - last processed upd message
.u.asg.roll:{[h;subI]
    .util.lg "Rolling subscriber on handle ", string h;

    cfg: exec from .u.asg.tab where handle = h;
    update rolled:.z.p, lastI:subI from `.u.asg.tab where handle = h;
    .u.del[;h] each cfg`tabs;
    if[count queue: select from .u.asg.tab where null live, null rolled, queue = cfg`queue;
            .u.asg.add . first[queue]`tabs`syms`handle];

    show .u.asg.tab;
 };

.u.asg.end:{[]
    .util.lg "End of Day has occured";
    .util.lg "Sending .u.end to rolled subscribers";

    rolled: exec handle from .u.asg.tab where not null handle, not null rolled;
    rolled @\: (`.u.end; .u.d);
    delete from `.u.asg.tab where not null rolled;

    show .u.asg.tab;
 };

/ h - handle of disconnected subscriber
.u.asg.zpc:{[h]
    .util.lg "Process on handle ",string[h]," has disconnected";

    if[not null first exec live from .u.asg.tab where handle = h;
            .u.asg.roll[h;0]];
    update handle:0Ni from `.u.asg.tab where handle = h;
 };
