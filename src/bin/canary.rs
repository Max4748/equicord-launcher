use equicord_launcher::discord::Branch;

fn main() {
    if let Err(e) = equicord_launcher::launcher::run(Branch::Canary) {
        eprintln!("[equicord-launcher] Erreur : {e}");
        std::process::exit(1);
    }
}
