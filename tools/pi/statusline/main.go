package main

// The renderer is copied from the user's Claude dotfiles. Never inspect Claude
// session badges from Pi: they describe a different application/account.
func sessionBadge(_ bool, _ *string) string { return "" }
func main()                                 { runStatusline(nil) }
