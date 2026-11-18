use equicord_launcher::discord::Branch;

fn main() {
    if let Err(e) = equicord_launcher::launcher::run(Branch::Ptb) {
        eprintln!("[equicord-launcher] Erreur : {e}");
        std::process::exit(1);
    }
}
