
/ (`.u.stream; `:tplog/sym2020.01.01; 100; 200)
.u.stream:{[tplog;start;end]
    .util.lg "Streaming ",string[tplog]," to process on handle ",string .z.w;
    .util.lg "Between upd ",string[start]," and ",string end;

    .u.i:0;
    .u.start: start;
    i:-11!(end;tplog);

    .util.lg "Streamed ",string[i]," upds";
    delete i,start from `.u;
 };

upd: {if[.u.start < .u.i+:1; neg[.z.w] @ (`upd;x;y); neg[.z.w][]]};
