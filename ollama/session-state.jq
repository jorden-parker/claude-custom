{hasCompletedOnboarding: true}
+ (if (.theme | type) == "string" then {theme} else {} end)
+ (if (.projects | type) == "object"
    and (.projects[$root] | type) == "object"
    and .projects[$root].hasTrustDialogAccepted == true
  then {projects: {($root): {hasTrustDialogAccepted: true}}}
  else {} end)
