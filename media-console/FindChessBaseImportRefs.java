// @category Analysis
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.symbol.Reference;

public class FindChessBaseImportRefs extends GhidraScript {
    @Override
    public void run() throws Exception {
        Address[] imports = {toAddr("140fb3dc6")};
        for (Address address : imports) {
            println("IMPORT " + address);
            for (Reference ref : getReferencesTo(address)) {
                Function f = getFunctionContaining(ref.getFromAddress());
                println("  REF " + ref.getFromAddress() + " "
                        + (f == null ? "<none>" : f.getEntryPoint() + " " + f.getName()));
            }
        }
    }
}
