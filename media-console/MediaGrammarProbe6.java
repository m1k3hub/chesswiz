// MediaGrammarProbe6.java
// @category Analysis
// Q1: resolve the board-side consumer object stored at media-window +0x248
// and decompile its vtable+0x480 method (the GA/TEXT payload consumer that
// must dispatch wire opcodes 2/3/4/6/8/14).
//
// Ground truth (probes 3+5, /tmp/ghidra_out3.log, /tmp/ghidra_out5.log):
//   FUN_1403a88a0 (timer dispatch) and FUN_1403a8590 (command dispatch)
//   both call  (**(code **)(*consumer + 0x480))(consumer, action, payload,
//   window+0x290, 0)  with consumer = *(window + 0x248).
//   The consumer also receives vtable +0x488 (COMMAND) and +0x490 (QUERY,
//   returns a double seek target).
//
// Strategy:
//  A) Sweep symbols named "vftable" (MSVC RTTI namespaces): any class whose
//     vtable has code pointers at +0x480/+0x488/+0x490 is the consumer
//     candidate; decompile the +0x480 target of the name-interesting ones.
//  B) Window class trace: refs to FUN_1403a8590 (a virtual itself) hit the
//     media window's vtable in .rdata -> class name; refs to that vtable hit
//     the window ctor(s) that must assign *(param_1 + 0x248) = new <class>.
//  C) Decompile FUN_140f20e40 (the in-binary transport decoder used by the
//     Sequence-column formatter FUN_1403ac000 for GA/TEXT payloads) and its
//     callers: the consumer's +0x480 method must decode via the same entry.

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.Namespace;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolIterator;
import java.util.ArrayList;

public class MediaGrammarProbe6 extends GhidraScript {

    private void dump(DecompInterface decomp, Function f, int limit) {
        println("==== DECOMP " + f.getEntryPoint() + " " + f.getName() + " ====");
        DecompileResults res = decomp.decompileFunction(f, 150, monitor);
        if (res != null && res.getDecompiledFunction() != null) {
            String c = res.getDecompiledFunction().getC();
            if (c.length() > limit) c = c.substring(0, limit) + "\n...TRUNC";
            println(c);
        } else {
            println("  decompile failed");
        }
    }

    private Address codePtr(Memory mem, Address a) {
        try {
            long v = mem.getLong(a);
            Address p = toAddr(v);
            MemoryBlock b = mem.getBlock(p);
            if (b != null && b.isExecute()) return p;
        } catch (Exception e) { /* unreadable/crosses block end */ }
        return null;
    }

    private String fullName(Symbol s) {
        if (s == null) return "?";
        Namespace ns = s.getParentNamespace();
        String parent = (ns == null) ? "" : ns.getName(true);
        return parent + "::" + s.getName();
    }

    @Override
    public void run() throws Exception {
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        Memory mem = currentProgram.getMemory();

        // ---------------------------------------------------------------
        println("### A) vftables with a code slot at +0x480 (consumer candidates)");
        SymbolIterator it = currentProgram.getSymbolTable().getSymbols("vftable");
        int total = 0;
        int shown = 0;
        int decompiled = 0;
        while (it.hasNext()) {
            Symbol s = it.next();
            Address va = s.getAddress();
            MemoryBlock blk = mem.getBlock(va);
            if (blk == null || blk.isExecute()) continue;
            Address e480 = codePtr(mem, va.add(0x480));
            if (e480 == null) continue;
            Address e488 = codePtr(mem, va.add(0x488));
            Address e490 = codePtr(mem, va.add(0x490));
            total++;
            String fqn = fullName(s);
            String low = fqn.toLowerCase();
            boolean interesting = low.contains("board") || low.contains("media")
                || low.contains("view") || low.contains("game")
                || low.contains("play") || low.contains("script")
                || low.contains("notat") || low.contains("train");
            if (interesting || shown < 150) {
                Function fp = getFunctionAt(e480);
                println((interesting ? "*** " : "    ") + "VT " + va + " " + fqn
                    + " +480=" + e480 + (fp != null ? " fn=" + fp.getName() : "")
                    + " +488=" + e488 + " +490=" + e490);
                if (!interesting) shown++;
            }
            if (interesting && decompiled < 3) {
                Function f = getFunctionAt(e480);
                if (f != null) { dump(decomp, f, 60000); decompiled++; }
            }
        }
        println("### vftables with +0x480 code slot total: " + total);

        // ---------------------------------------------------------------
        println("### B) window-class trace via refs to FUN_1403a8590");
        Address disp2 = toAddr(0x1403a8590L);
        ArrayList<Address> done = new ArrayList<Address>();
        for (Reference ref : getReferencesTo(disp2)) {
            Address from = ref.getFromAddress();
            MemoryBlock fb = mem.getBlock(from);
            boolean isCode = (fb != null && fb.isExecute());
            println("REF " + (isCode ? "code" : "data") + " from " + from);
            if (isCode) {
                Function f = getFunctionContaining(from);
                if (f != null && !done.contains(f.getEntryPoint())) {
                    done.add(f.getEntryPoint());
                    dump(decomp, f, 40000);
                }
            } else {
                // probable vtable slot: walk back to the vftable symbol
                Address a = from;
                Symbol vs = null;
                for (int i = 0; i < 160; i++) {
                    Symbol sym = currentProgram.getSymbolTable().getPrimarySymbol(a);
                    if (sym != null && sym.getName().contains("vft")) { vs = sym; break; }
                    a = a.subtract(8);
                }
                if (vs != null) {
                    println(">>> window vtable " + vs.getAddress() + " class "
                            + fullName(vs) + " (slot offset "
                            + from.subtract(vs.getAddress()) + ")");
                    int n = 0;
                    for (Reference r2 : getReferencesTo(vs.getAddress())) {
                        Function f2 = getFunctionContaining(r2.getFromAddress());
                        if (f2 == null || done.contains(f2.getEntryPoint())) continue;
                        done.add(f2.getEntryPoint());
                        println(">>> VTABLE REF (ctor?) " + f2.getEntryPoint()
                                + " " + f2.getName());
                        dump(decomp, f2, 40000);
                        if (++n >= 3) break;
                    }
                } else {
                    println(">>> data ref at " + from + " : no vftable symbol above");
                }
            }
        }

        // ---------------------------------------------------------------
        println("### C) transport decoder FUN_140f20e40 and its callers");
        Address dec = toAddr(0x140f20e40L);
        Function df = getFunctionAt(dec);
        if (df != null) dump(decomp, df, 40000);
        int dn = 0;
        ArrayList<Address> dseen = new ArrayList<Address>();
        for (Reference ref : getReferencesTo(dec)) {
            Function f = getFunctionContaining(ref.getFromAddress());
            if (f == null || dseen.contains(f.getEntryPoint())) continue;
            dseen.add(f.getEntryPoint());
            if (f.getEntryPoint().equals(dec)) continue;
            println(">>> DECODER CALLER " + f.getEntryPoint() + " " + f.getName());
            dump(decomp, f, 40000);
            if (++dn >= 12) break;
        }
        println("### decoder callers shown: " + dn);

        decomp.dispose();
    }
}
