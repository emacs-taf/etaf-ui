;;; etaf-ui-markdown-tests.el --- Public API acceptance -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:
;; Test the supported markdown parsing and rendering contract: document
;; structure, dialects, block and inline rendering, the environment
;; callbacks and the documented errors.  Internal helpers are outside this
;; contract.

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'etaf-ui)

(defconst etaf-ui-markdown-test--palette
  '((:ink . "#1f2328") (:muted . "#59636e") (:faint . "#818b98")
    (:accent . "#0969da") (:accent-soft . "#ddf4ff") (:border . "#d1d9e0")
    (:panel . "#f6f8fa") (:panel2 . "#eef1f4") (:quote-bar . "#d1d9e0")
    (:quote-bg . "#f9fbfd") (:table-header . "#f0f3f6")
    (:table-stripe . "#fbfcfd") (:heading . "#1f2328") (:heading-rule . "#d1d9e0")
    (:ok . "#1a7f37") (:ok-soft . "#dafbe1") (:warn . "#9a6700")
    (:warn-soft . "#fff8c5") (:danger . "#d1242f") (:danger-soft . "#ffebe9")
    (:important . "#8250df") (:important-soft . "#fbefff"))
  "Palette covering every semantic key the markdown renderer reads.")

(defvar etaf-ui-markdown-test--code-calls 0
  "Number of `:render-code-block' calls of the current test.")

(defvar etaf-ui-markdown-test--media-calls 0
  "Number of `:render-media' calls of the current test.")

(defun etaf-ui-markdown-test--env (&rest overrides)
  "Return a rendering environment with OVERRIDES applied."
  (append overrides (list :palette etaf-ui-markdown-test--palette)))

(defun etaf-ui-markdown-test--mount (text env)
  "Mount TEXT rendered with ENV and return the buffer name."
  (let* ((document (etaf-ui-markdown-parse text))
         (env (append env (list :features (plist-get document :features))))
         (views (etaf-ui-markdown-view-blocks (plist-get document :children) env))
         (buffer-name (format " *etaf-ui-markdown-%s*" (cl-gensym))))
    (etaf-mount buffer-name
                (etaf-node 'column (list :width '(ch 60)) views))
    buffer-name))

(defun etaf-ui-markdown-test--text (buffer-name)
  "Return the plain text published in BUFFER-NAME."
  (with-current-buffer buffer-name
    (substring-no-properties (buffer-string))))

(defmacro etaf-ui-markdown-test--with-mount (text env &rest body)
  "Mount TEXT rendered with ENV, evaluate BODY, then release the runtime."
  (declare (indent 2))
  `(let ((buffer-name (etaf-ui-markdown-test--mount ,text ,env)))
     (unwind-protect
         (progn ,@body)
       (when-let* ((runtime (etaf-runtime-for-buffer buffer-name)))
         (etaf-unmount runtime))
       (when-let* ((buffer (get-buffer buffer-name)))
         (kill-buffer buffer)))))

(ert-deftest etaf-ui-markdown-parse-reports-document-structure ()
  "Parsing exposes the title, outline, blocks, footnotes and features."
  (let* ((document (etaf-ui-markdown-parse
                    "---\ntitle: Doc\n---\n\n# Intro\n\nText[^a].\n\n## Part\n\n[^a]: note\n"))
         (blocks (plist-get document :children))
         (types (mapcar (lambda (block) (plist-get block :type)) blocks)))
    (should (equal "Doc" (plist-get document :title)))
    (should (equal '((1 "Intro" "intro") (2 "Part" "part"))
                   (plist-get document :outline)))
    (should (equal '(heading paragraph heading) types))
    (should (equal '("a") (mapcar (lambda (note) (plist-get note :label))
                                  (plist-get document :footnotes))))
    (should (eq t (plist-get (plist-get document :features) :tables)))))

(ert-deftest etaf-ui-markdown-parse-dialect-gates-extensions ()
  "The `commonmark' dialect leaves GitHub extensions as literal text."
  (let ((gfm (etaf-ui-markdown-parse "| a | b |\n| --- | --- |\n| 1 | 2 |\n"))
        (core (etaf-ui-markdown-parse "| a | b |\n| --- | --- |\n| 1 | 2 |\n"
                                      'commonmark)))
    (should (eq 'table (plist-get (car (plist-get gfm :children)) :type)))
    (should-not (eq 'table (plist-get (car (plist-get core :children)) :type)))))

(ert-deftest etaf-ui-markdown-parse-rejects-unknown-flavor ()
  "An unknown dialect name signals the documented error."
  (should-error (etaf-ui-markdown-parse "# x\n" 'markdown-extras)
                :type 'etaf-ui-markdown-error))

(ert-deftest etaf-ui-markdown-render-requires-a-palette ()
  "Rendering a colored block without its palette signals the error."
  (let ((blocks (plist-get (etaf-ui-markdown-parse "## Heading\n") :children)))
    (should-error (etaf-ui-markdown-view-blocks blocks (list))
                  :type 'etaf-ui-markdown-error)
    (should-error (etaf-ui-markdown-view-blocks
                   blocks (list :palette '((:ink . "#000000"))))
                  :type 'etaf-ui-markdown-error)))

(ert-deftest etaf-ui-markdown-renders-blocks-and-inline-styles ()
  "A document renders headings, lists, code, tables, quotes and alerts."
  (let ((text (concat "# Title\n\n"
                      "<!-- index: invisible marker -->\n\n"
                      "Plain **bold** and `code` paragraph.\n\n"
                      "- first\n- second\n\n"
                      "```elisp\n(message \"hi\")\n```\n\n"
                      "| Name | Value |\n| --- | --- |\n| alpha | 1 |\n\n"
                      "> quoted line\n\n"
                      "> [!NOTE]\n> alert body\n")))
    (etaf-ui-markdown-test--with-mount
        text (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (string-match-p "Title" published))
        (should-not (string-match-p "index: invisible" published))
        (should (string-match-p "Plain bold and code paragraph\\." published))
        (should (string-match-p "• first" published))
        (should (string-match-p "(message \"hi\")" published))
        (should (string-match-p "alpha" published))
        (should (string-match-p "quoted line" published))
        (should (string-match-p "Note" published))
        (should (string-match-p "alert body" published))))))

(ert-deftest etaf-ui-markdown-callbacks-replace-media-and-code ()
  "`:render-code-block' and `:render-media' own the rendered block."
  (setq etaf-ui-markdown-test--code-calls 0
        etaf-ui-markdown-test--media-calls 0)
  (let ((env (etaf-ui-markdown-test--env
              :render-code-block
              (lambda (block env)
                (ignore block env)
                (setq etaf-ui-markdown-test--code-calls
                      (1+ etaf-ui-markdown-test--code-calls))
                (etaf-node 'text nil (list "CUSTOM-CODE")))
              :render-media
              (lambda (kind node env)
                (ignore kind node env)
                (setq etaf-ui-markdown-test--media-calls
                      (1+ etaf-ui-markdown-test--media-calls))
                (etaf-node 'text nil (list "CUSTOM-MEDIA"))))))
    (etaf-ui-markdown-test--with-mount
        "```\nraw code\n```\n\n![alt text](missing.png)\n" env
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (= 1 etaf-ui-markdown-test--code-calls))
        (should (= 1 etaf-ui-markdown-test--media-calls))
        (should (string-match-p "CUSTOM-CODE" published))
        (should (string-match-p "CUSTOM-MEDIA" published))
        (should-not (string-match-p "raw code" published))))))

(ert-deftest etaf-ui-markdown-media-falls-back-to-text ()
  "Without `:render-media' an image renders as its alt text."
  (etaf-ui-markdown-test--with-mount
      "![the alt text](missing.png)\n" (etaf-ui-markdown-test--env)
    (should (string-match-p "\\[the alt text\\]"
                            (etaf-ui-markdown-test--text buffer-name)))))

(ert-deftest etaf-ui-markdown-alert-labels-override-defaults ()
  "`:alert-labels' replaces the callout label of its kind only."
  (etaf-ui-markdown-test--with-mount
      "> [!WARNING]\n> body\n" (etaf-ui-markdown-test--env
                                :alert-labels '((warning . "当心")))
    (let ((published (etaf-ui-markdown-test--text buffer-name)))
      (should (string-match-p "当心" published))
      (should-not (string-match-p "Warning" published)))))

(defun etaf-ui-markdown-test--scaled-text (buffer-name)
  "Return the published characters of BUFFER-NAME whose face sets a height."
  (with-current-buffer buffer-name
    (let ((scaled nil))
      (dotimes (index (buffer-size))
        (let ((faces (get-text-property (1+ index) 'face)))
          (when (cl-some (lambda (face)
                           (and (consp face) (keywordp (car face))
                                (plist-get face :height)))
                         (if (and (consp faces) (keywordp (car faces)))
                             (list faces)
                           (ensure-list faces)))
            (push (char-after (1+ index)) scaled))))
      (concat (nreverse scaled)))))

(ert-deftest etaf-ui-markdown-line-grid-keeps-body-size ()
  "`:line-grid' renders headings and footnote references at the body size."
  (let ((text "# Title\n\n## Part\n\nBody[^n]\n\n[^n]: note\n"))
    (etaf-ui-markdown-test--with-mount text (etaf-ui-markdown-test--env)
      (let ((scaled (etaf-ui-markdown-test--scaled-text buffer-name)))
        (should (string-match-p "Title" scaled))
        (should (string-match-p "Part" scaled))))
    (etaf-ui-markdown-test--with-mount
        text (etaf-ui-markdown-test--env :line-grid t)
      (let ((scaled (etaf-ui-markdown-test--scaled-text buffer-name))
            (published (etaf-ui-markdown-test--text buffer-name)))
        (should (equal "" scaled))
        (should (string-match-p "Title" published))
        (should (string-match-p "Part" published))))))

(ert-deftest etaf-ui-markdown-table-columns-follow-content ()
  "Table columns take width in proportion to their content and wrap by word."
  (let ((long "alpha bravo charlie delta echo foxtrot"))
    (etaf-ui-markdown-test--with-mount
        (format "| k | text |\n| --- | --- |\n| a | %s |\n" long)
        (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (string-match-p (regexp-quote long) published))))
    (etaf-ui-markdown-test--with-mount
        (format "| text | more |\n| --- | --- |\n| %s | %s |\n" long long)
        (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (dolist (word (split-string long))
          (should (string-match-p (format "\\_<%s\\_>" word) published)))))))

(ert-deftest etaf-ui-markdown-table-keeps-unbroken-columns ()
  "A column is never narrower than the widest unbreakable cell text."
  (let ((identifier "etaf-manual-reader--section")
        (prose (concat "this is a very long description with many many words "
                       "that push the fraction to the cap")))
    (etaf-ui-markdown-test--with-mount
        (format "| Property | Inheritance | Meaning |\n| --- | --- | --- |\n| `%s` | 继承 | %s |\n"
                identifier prose)
        (etaf-ui-markdown-test--env)
      (let ((published (etaf-ui-markdown-test--text buffer-name)))
        (should (string-match-p (regexp-quote identifier) published))
        (should (string-match-p "继承" published))))))

(provide 'etaf-ui-markdown-tests)
;;; etaf-ui-markdown-tests.el ends here
