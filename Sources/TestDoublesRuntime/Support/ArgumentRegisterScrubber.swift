import CTestDoublesTrampoline

/// Forces matcher placeholders through an opaque generic return after every
/// captured C argument register has been overwritten. A concrete frozen
/// caller must reload a direct value after this boundary; an indirect caller
/// passes the returned storage address instead.
@inline(never)
package func scrubArgumentRegisters() {
    td_scrub_argument_registers(
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0
    )
}
