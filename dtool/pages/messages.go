package pages

// NavigateMsg tells the app to switch pages.
type NavigateMsg struct {
	Target string
}

// TaskDoneMsg signals that an async task completed.
type TaskDoneMsg struct {
	Label   string
	Output  string
	Err     error
	FreedKB int64
}

// SudoCleanDoneMsg signals the sudo phase of cleanup finished. The cleaner
// reads PendingNonSudo and kicks off the non-sudo phase.
type SudoCleanDoneMsg struct {
	Results        []string
	FreedKB        int64
	PendingNonSudo []int
	DryRun         bool
	Err            error
}

// ScanResultMsg carries results from a filesystem scan.
type ScanResultMsg struct {
	Items []ScanItem
}

type ScanItem struct {
	Path    string
	SizeKB  int64
	ModTime string
}

// BranchListMsg carries git branch info.
type BranchListMsg struct {
	Current  string
	Branches []string
	Err      error
}

// DiskListMsg carries diskutil output.
type DiskListMsg struct {
	Output string
	Err    error
}
