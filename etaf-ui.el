;;; etaf-ui.el --- Official ETAF Component catalog -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later
;; Author: ETAF contributors
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (etaf "0.1.0"))
;; URL: https://github.com/ginqi7/etaf-ui

;;; Commentary:

;; Public facade for Components defined with ETAF.  The catalog exposes no
;; second Widget runtime, Theme system, data store, or layout engine.

;;; Code:

(require 'etaf-ui-basic)
(require 'etaf-ui-table)
(require 'etaf-ui-data)

(provide 'etaf-ui)
;;; etaf-ui.el ends here
