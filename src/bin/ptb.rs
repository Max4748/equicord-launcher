// Pas de fenêtre console au lancement sous Windows (voir launcher::main).
#![windows_subsystem = "windows"]

use equicord_launcher::discord::Branch;

fn main() {
    equicord_launcher::launcher::main(Branch::Ptb);
}
