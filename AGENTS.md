## 通用行为准则

1. 任何涉及到 Popover 和 Setting UI 的变动，都需要在 `docs/prototypes/` 中先给出 popover.html 和 setting.html 原型，同意后再进行代码修改；
2. 任何情况下 mian 分支都不允许提交代码，如果有代码改动，则必须新建一个临时分支，提交代码后合并到 main 分支，每次合并代码之前必须询问用户；
3. readme.md 文件不需要说明技术方案和产品进化过程中的细节，只需要关注当前是什么、有什么，简单说明即可；

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five roles: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: root `GLOSSARY.md` + `docs/adr/`. See `docs/agents/domain.md`.
