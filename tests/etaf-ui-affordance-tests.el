;;; etaf-ui-affordance-tests.el --- Native control feedback -*- lexical-binding: t; -*-

;;; Commentary:
;; Check native feedback through supported component and rendering interfaces.

;;; Code:
(require 'ert)
(require 'etaf-ui)
(require 'ebox)

(ert-deftest etaf-ui-control-forwards-native-feedback ()
  "Native root attributes reach Ebox through the public Button component."
  (dolist (hover '(nil (:background-color "#abcdef")))
    (let* ((output (ebox-render
                    (etaf-render
                     (etaf-view
                      (box :hover-style '(:background-color "#123456")
                           (etaf-button :label "Custom" :pointer 'arrow :help-echo "Help"
                                        :hover-style hover))))))
           (position (string-match "Custom" output)))
      (should position)
      (should (eq 'arrow (get-text-property position 'pointer output)))
      (should (equal "Help" (get-text-property position 'help-echo output)))
      (if hover
          (should (string-match-p "#abcdef"
                                  (format "%S" (get-text-property position 'mouse-face output))))
        (should-not (get-text-property position 'mouse-face output))))))

(provide 'etaf-ui-affordance-tests)
;;; etaf-ui-affordance-tests.el ends here
