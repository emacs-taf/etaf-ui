;;; etaf-ui-advanced.el --- Advanced composed ETAF UI Components -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Date, tree, calendar and command-palette Components compose the catalog's
;; controlled inputs, disclosure and floating surface contracts.

;;; Code:
(require 'calendar)
(require 'cl-lib)
(require 'etaf-ui-input)
(require 'etaf-ui-navigation)
(require 'etaf-ui-surface)
(require 'etaf-ui-table)

(etaf-define-component etaf-date-picker
    (&key (value etaf-ui--unsupplied) (label "Date")
          (on-change etaf-ui--unsupplied) disabled bind)
  "Render a semantic DATE-PICKER through the shared date input boundary."
  :render
  (etaf-node 'etaf-input
             (list :type 'date :value value :label label :disabled disabled
                   :on-change on-change :bind bind)
             nil))

(defun etaf-ui--tree-items (items expanded)
  "Validate all ITEMS and return visible entries under EXPANDED keys."
  (let ((seen (make-hash-table :test #'equal)))
    (cl-labels
        ((walk (nodes depth visible)
           (etaf-check-prop :items nodes (proper-list-p nodes)
                            "a list of tree items" 'etaf-tree)
           (cl-mapcan
            (lambda (item)
              (etaf-check-prop
               :items item
               (and (proper-list-p item) (zerop (% (length item) 2))
                    (plist-get item :key)
                    (let ((key (plist-get item :key)))
                      (or (symbolp key) (stringp key) (numberp key)))
                    (stringp (plist-get item :label))
                    (not (string-empty-p (plist-get item :label)))
                    (not (gethash (plist-get item :key) seen)))
               "items with globally unique scalar keys and nonempty labels" 'etaf-tree)
              (let* ((key (plist-get item :key))
                     (children (plist-get item :children)))
                (puthash key t seen)
                (append
                 (when visible
                   (list (list :key key :label (plist-get item :label)
                               :depth depth :branch (and children t))))
                 (walk children (1+ depth) (and visible (member key expanded))))))
            nodes)))
      (walk items 0 t))))

(etaf-define-component etaf-tree (&key items expanded on-toggle on-select)
  "Render a controlled TREE with nested :children item plists.
EXPANDED is a caller-owned list of open keys; callbacks receive a key or the
next expanded key list."
  :validate
  (progn
    (etaf-check-prop :items items (and (proper-list-p items) items)
                     "a nonempty list of tree items" 'etaf-tree)
    (etaf-check-prop :on-toggle on-toggle (or (null on-toggle) (functionp on-toggle))
                     "a function or nil" 'etaf-tree)
    (etaf-check-prop :on-select on-select (or (null on-select) (functionp on-select))
                     "a function or nil" 'etaf-tree))
  :render
  (let* ((expanded (etaf-ui--reactive-value expanded))
         (_ (etaf-check-prop :expanded expanded (proper-list-p expanded)
                             "a list of expanded keys" 'etaf-tree))
         (flat (etaf-ui--tree-items items expanded)))
    (etaf-view
     (column :class "etaf-tree" :width 'stretch :item-gap '(lh 0)
       (expr
        (mapcar
         (lambda (entry)
           (let* ((key (plist-get entry :key))
                  (branch (plist-get entry :branch))
                  (open (member key expanded))
                  (prefix (make-string (* 2 (plist-get entry :depth)) ?\s))
                  (caption (concat prefix (if branch (if open "▾ " "▸ ") "  ")
                                   (plist-get entry :label))))
             (etaf-view
              (etaf-button :label caption :variant (if open 'secondary 'ghost)
                           :aria-label (plist-get entry :label)
                           :on-press
                           (lambda ()
                             (if branch
                                 (when on-toggle
                                   (funcall on-toggle
                                            (if open (delete key (copy-sequence expanded))
                                              (cons key (copy-sequence expanded)))))
                               (when on-select (funcall on-select key))))))))
         flat))))))

(etaf-define-component etaf-calendar
    (&key (month '(2026 1)) value on-change (label "Calendar"))
  "Render a controlled month CALENDAR as (YEAR MONTH) and date VALUE.
ON-CHANGE receives (YEAR MONTH DAY)."
  :validate
  (progn
    (etaf-check-prop :month month (and (proper-list-p month) (= (length month) 2)
                                       (integerp (car month)) (integerp (cadr month))
                                       (<= 1 (cadr month) 12))
                     "a (YEAR MONTH) list" 'etaf-calendar)
    (etaf-check-prop :value value (or (null value) (integerp value))
                     "an integer day or nil" 'etaf-calendar)
    (etaf-check-prop :on-change on-change (or (null on-change) (functionp on-change))
                     "a function or nil" 'etaf-calendar))
  :render
  (let* ((year (car month)) (number (cadr month))
         (first (mod (1- (calendar-day-of-week (list number 1 year))) 7))
         (last (calendar-last-day-of-month number year))
         (name (calendar-month-name number))
         (cells (append (make-list first nil) (number-sequence 1 last)))
         (rows (cl-loop for start from 0 below (length cells) by 7
                        collect (cl-subseq cells start (min (+ start 7) (length cells)))))
         (week-days '("Mo" "Tu" "We" "Th" "Fr" "Sa" "Su"))
         (week-views
          (mapcar (lambda (day) (etaf-node 'etaf-label (list :text day :variant 'muted) nil))
                  week-days))
         (row-views
          (mapcar
           (lambda (calendar-row)
             (etaf-node 'row (list :item-gap '(ch 1))
                        (mapcar
                         (lambda (day)
                           (if day
                               (etaf-node
                                'etaf-button
                                (list :label (format "%2d" day)
                                      :variant (if (equal day value) 'secondary 'ghost)
                                      :aria-label (format "%s %d" name day)
                                      :on-press
                                      (and on-change
                                           (lambda ()
                                             (funcall on-change (list year number day)))))
                                nil)
                             (etaf-node 'etaf-label (list :text "  ") nil)))
                         calendar-row)))
           rows)))
    (etaf-node
     'column
     (list :class "etaf-calendar" :width 'stretch :item-gap '(lh 1))
     (append
      (list (etaf-node 'row (list :item-gap '(ch 1))
                       (list (etaf-node 'etaf-label (list :text label :variant 'strong) nil)
                             (etaf-node 'etaf-label
                                        (list :text (format "%s %d" name year)
                                              :variant 'muted) nil)))
            (etaf-node 'row (list :item-gap '(ch 1)) week-views))
      row-views))))

(etaf-define-component etaf-command-palette
    (&key open (title "Command palette") items on-select on-close)
  "Render a controlled COMMAND-PALETTE from LIST ITEMS in a modal Dialog."
  :validate
  (etaf-check-prop :on-close on-close (functionp on-close)
                   "a function" 'etaf-command-palette)
  :render
  (when (etaf-ui--reactive-value open)
    (etaf-node 'etaf-dialog
               (list :open open :title title :on-close on-close :width '(ch 56))
               (list (etaf-node 'etaf-list
                                (list :items items :on-select on-select) nil)))))

(provide 'etaf-ui-advanced)
;;; etaf-ui-advanced.el ends here
