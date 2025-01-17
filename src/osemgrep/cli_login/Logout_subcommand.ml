(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(*
   Parse a semgrep-logout command, execute it and exit.

   Translated from login.py
*)

(*****************************************************************************)
(* Main logic *)
(*****************************************************************************)

(* All the business logic after command-line parsing. Return the desired
   exit code. *)
let run (conf : Login_CLI.conf) : Exit_code.t =
  Logs_helpers.setup_logging ~force_color:false ~level:conf.logging_level;
  let settings = Semgrep_settings.get () in
  let settings = Semgrep_settings.{ settings with api_token = None } in
  Semgrep_settings.save settings;
  Exit_code.ok

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let main (argv : string array) : Exit_code.t =
  let conf = Login_CLI.parse_argv Login_CLI.logout_cmdline_info argv in
  run conf
