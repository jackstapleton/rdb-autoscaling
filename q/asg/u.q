// asg/u.q

/ .u.add and .u.sub changed to take handle as a 3rd argument instead of using .z.w
\d .u
/ use 'z' instead of .z.w
add:{$[(count w x)>i:w[x;;0]?z;.[`.u.w;(x;i;1);union;y];w[x],:enlist(z;y)];(x;$[99=type v:value x;sel[v]y;@[0#v;`sym;`g#]])}

/ use 'z' instead of .z.w, and input as 3rd argument to .u.add
subInner:{if[x~`;:subInner[;y;z]each t];if[not x in t;'x];del[x]z;add[x;y;z]}
sub:{subInner[x;y;.z.w]}
\d .

/ table used to handle subscriptions
/   time   - time the subscriber was added
/   handle - handle of the subscriber
/   tabs   - tables the subscriber has subscribed for
/   syms   - syms the subscriber has subscribed for
/   ip     - ip of the subscriber
/   queue  - queue the subscriber is a part of
/   live   - time the tickerplant addd the subscriber to .u.w
/   rolled - time the subscriber unsubscribed
/   firstI - upd count when subscriber became live
/   lastI  - last upd subscriber processed
.u.asg.tab: flip `time`handle`tabs`syms`queue`live`rolled`lastI!();
`.u.asg.tab upsert (0Np;0Ni;();();`;0Np;0Np;0N);

/ t - A list of tables (or ` for all).
/ s - Lists of symbol lists for each of the tables.
/ q - The name of the queue to be added to.
.u.asg.sub:{[t;s;q]
    if[-11h = type t;
            t: enlist t;
            s: enlist s];

    if[not (=) . count each (t;s);
            '"Count of table and symbol lists must match"];

    if[not all missing: t in .u.t,`;
            '.Q.s1[t where not missing]," not available"];

    `.u.asg.tab upsert (.z.p; .z.w; t; s; `$"." sv string 256 vs .z.a; q; 0Np; 0Np; 0N; 0N);
    liveProc: select from .u.asg.tab where not null handle,
                                           not null live,
                                           null rolled,
                                           queue = q;
    if[not count liveProc; .u.asg.add[t;s;.z.w]];
 };

/ t - List of tables the RDB wants to subscribe to.
/ s - Symbol lists the RDB wants to subscribe to.
/ h - The handle of the RDB.
.u.asg.add:{[t;s;h]
    schemas: raze .u.subInner[;;h] .' flip (t;s);
    q: first exec queue from .u.asg.tab where handle = h;
    startI: max 0^ exec lastI from .u.asg.tab where queue = q;
    neg[h] (`.sub.rep; schemas; .u.L; (startI; .u.i));
    update live:.z.p, firstI:startI from `.u.asg.tab where handle = h;
 };

/ h    - handle of the RDB
/ subI - last processed upd message
.u.asg.roll:{[h;subI]
    .u.del[;h] each .u.t;
    update rolled:.z.p, lastI:subI from `.u.asg.tab where handle = h;
    q: first exec queue from .u.asg.tab where handle = h;
    waiting: select from .u.asg.tab where not null handle,
                                          null live,
                                          queue = q;
    if[count waiting; .u.asg.add . first[waiting]`tabs`syms`handle];
 };

/ h - handle of disconnected subscriber
.u.asg.zpc:{[h]
    if[not null first exec live from .u.asg.tab where handle = h; .u.asg.roll[h;0]];
    update handle:0Ni from `.u.asg.tab where handle = h;
 };

/ send .u.end to all non live subs with a handle
/ clear all disconnected procs from .u.asg.tab
/ mark all firstI and as zero
.u.asg.end:{[]
    delete from `.u.asg.tab where null handle;
    notLive: exec handle from .u.asg.tab where (null live) or not any null (live;rolled);
    neg[notLive] @\: (`.u.end; dt);
    update firstI:0 from `.u.asg.tab where not null live;
 };
