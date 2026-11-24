::application::switchTab board; update
::application::assistant::panel::Hide; update
::application::assistant::panel::Show; update; after 300; update
set t [::application::twm board]
list [::application::twm::inspectLayout $t] [winfo width [$t leaf assistant]] [winfo ismapped [$t leaf assistant]]
