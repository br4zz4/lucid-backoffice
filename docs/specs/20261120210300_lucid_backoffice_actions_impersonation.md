---
title: lucid-backoffice v0.2 — DSL de ações corretivas, editable e impersonação
status: proposed
created: 2026-11-20
updated: 2026-11-20
owner: "@oporpino"
certainty: high
---

# lucid-backoffice v0.2 — DSL de ações corretivas, editable e impersonação

> **TLDR**: adicionar ao `lucid-backoffice` uma DSL declarativa de Ação corretiva (alvo registro/tenant/global, campos tipados, dedução automática de prévia e verificação de estado, `only_if`/`unavailable`, `danger`, `perform` em bloco ou `with:` um `Lucid::Case::Command`), o atalho `editable` nos recursos e a impersonação somente leitura e mascarada, com ganchos de login fornecidos pelo app.

Spec 4 da sequência backoffice. Depende de `20261120210200_lucid_backoffice_core.md` (v0.1.0). Repo `br4zz4/lucid-backoffice`; copiada para `docs/specs/` do repo no PR 1.

# what

Como dev, quero declarar em poucas linhas o que o backoffice pode escrever (uma correção, um campo editável) e permitir ver o app como um usuário, sempre com prévia, motivo, permissão, máscara e trilha, sem ficar preso a um formato fixo de ação.

## out of scope

- Ações em lote (issue aberta na v0.1).
- Aprovação por dois operadores.
- Editar ou apagar genérico: só o que for declarado.
- Notificar alguém de uma impersonação (o app decide; a gem só registra).
- Login do app (a gem chama ganchos).

## acceptance criteria

### Ações

    Cenário: ação mínima com dedução
      Dado
        class ChangeUserRole < Lucid::Backoffice::Action
          on :users
          field :role, :select, choices: -> { %w[teacher coordinator] }
          perform { record.update!(role:) }
        end
      Quando o operador com :run_action abre a ação no usuário 7 (role teacher) e escolhe coordinator
      Então o campo vem preenchido com teacher, a prévia mostra "role: teacher → coordinator" (mascarada pela categoria da coluna)
      E executar exige motivo de reveal_reason_min caracteres
      E grava role, e o evento "backoffice.action.change_user_role" com outcome ok, motivo e operador

    Cenário: estado mudou entre prévia e execução
      Dado a prévia aberta com role teacher
      Quando outro processo muda role para director antes de executar
      Então a execução falha com "o estado mudou, revise a prévia" e nada é gravado

    Cenário: indisponível com explicação
      Dado unavailable "Escola ficaria sem owner", if: -> { record.last_owner? }
      Então o botão aparece desabilitado com a explicação e um POST direto é recusado

    Cenário: only_if esconde
      Dado only_if { record.owner? }
      Então a ação não aparece em registros que não satisfazem

    Cenário: prévia própria
      Dado preview { |p| p.change new_owner, :role, to: "owner"; p.list "Versões", pending }
      Então a prévia mostra essas linhas e o snapshot é o estado lido para montá-las

    Cenário: alvo tenant e global
      Dado on :tenant (ou on :global)
      Então a ação aparece no detalhe do tenant (ou no painel inicial) com tenant disponível no bloco

    Cenário: danger high
      Dado danger :high
      Então executar exige digitar o identificador do tenant ou do registro

    Cenário: transaction false
      Dado transaction false e perform fazendo HTTP
      Então perform roda sem transação e o evento é gravado depois

    Cenário: perform with Command
      Dado perform with: User::ChangeRole (Lucid::Case::Command) e a integração lucid_case
      Então os campos viram attributes, erros de validates aparecem nos campos
      E uma falha com `result[:errors]` (guard `fail_if :last_owner?` do lucid-case, mensagem já traduzida em `user.change_role.last_owner`) mostra essa mensagem
      E uma falha sem `errors` mostra lucid_backoffice.actions.change_user_role.failures.last_owner, ou a mensagem genérica se a chave não existir
      E há o evento do Command e o evento backoffice.action.* com o mesmo request_id e o motivo

    Cenário: tipos de campo
      Então :string, :text, :integer, :boolean, :date, :select, :record (busca por id e colunas públicas) e partial: funcionam e validam o tipo no backend

    Cenário: sem permissão
      Quando um operador sem :run_action (ou sem a permission declarada na ação) abre ou executa
      Então 403

    Cenário: result
      Dado result { notice "3 migrations aplicadas" }
      Então a mensagem aparece após executar

### editable

    Cenário: editar campos declarados
      Dado o recurso organizations com editable :name, :city
      Então aparece a ação "Editar" com só esses campos, prévia antes/depois mascarada, motivo e evento
      E nenhum outro campo é aceito no POST
      E com editable ..., with: Organization::Update, o Command é chamado e seus eventos saem automaticamente

### Impersonação

    Cenário: iniciar
      Dado os ganchos config.impersonation.find_user, sign_in, sign_out (e entry_url quando o usuário vive em outro host)
      Quando um operador com :impersonate escolhe o usuário 7 e informa o motivo
      Então é levado ao app como o usuário 7, por um token de uso único e 60 s quando há outro host
      E há eventos backoffice.impersonation.start e .enter com motivo

    Cenário: somente leitura e banner
      Dado o app incluindo Lucid::Backoffice::ImpersonationGuard no ApplicationController
      Então todo POST/PATCH/PUT/DELETE (exceto sair) recebe 403 com aviso, e o layout do app mostra o banner (partial da gem) com contagem e sair
      E Lucid::Backoffice.impersonating? é true para o app bloquear o que mais precisar

    Cenário: máscara dentro da impersonação
      Dado o app incluindo Lucid::Backoffice::ImpersonationMask no ApplicationRecord
      Então colunas não públicas sem Revelação ativa do operador chegam mascaradas (texto "•••••", data reduzida a 1º de janeiro do ano), os records ficam readonly, e tabelas da gem não são afetadas

    Cenário: página vista
      Então cada GET gera backoffice.impersonation.page_view com controller, action e id inteiro

    Cenário: expiração e substituição
      Então a sessão expira após impersonation.duration (30 min) com end_reason expired, e uma nova impersonação do mesmo operador encerra a anterior (replaced)

    Cenário: token inválido
      Quando o token é reutilizado, vencido ou de outro tenant
      Então 404 e nenhuma sessão

    Cenário: API para o app
      Então Lucid::Backoffice::Impersonation.active_for(user:) e #end!(reason:) permitem ao app encerrar (ex.: revogação), e start aceita metadata só com ids

    Cenário: ator
      Então eventos gravados durante a impersonação têm o operador como ator e impersonation_id preenchido

# why

Ler resolve metade da investigação; a outra metade é corrigir com segurança e ver o que o usuário vê. As duas specs de ações (luneta e has_warranty) e a impersonação do luneta têm o mesmo esqueleto; na gem a DSL deduz o óbvio e deixa todo o resto aberto, que é o oposto do formato fixo do Avo.

# how

Regras como na v0.1 (TDD, minitest + dummy PostgreSQL, prefixo `test/lucid/backoffice/` nos testes unitários, CI, YARD, docs em inglês, i18n).

**Feature flag:** não (nova versão da gem; apps optam ao declarar ações/ganchos).

**Telas da gem:** `/actions/:action/new?target=...` (prévia), `POST /actions/:action` (executa), `/impersonations` (lista), `POST /impersonations`, `GET <entry>/lucid_backoffice/impersonation/enter` (montado no app pelo gerador), `DELETE .../impersonation`.

**Staging:** `staging: none` (gem).

## Desenho

**Action** (`app/backoffice/actions/*.rb`, `< Lucid::Backoffice::Action`): `on :<recurso>|:tenant|:global`, `label`, `permission` (padrão `:run_action`), `field name, type, choices:, default:, of:, scope:, partial:, required:`, `only_if(reason = nil) { }`, `unavailable msg, if:`, `preview { |p| p.change(record, attr, to:); p.list(title, items) }`, `perform { }` ou `perform with: Command`, `result { notice ... }`, `danger :normal|:high`, `transaction true|false`. Dedução: campo com nome de atributo do `record` → default, prévia e snapshot (digest dos valores lidos). Execução: autoriza → recalcula snapshot (`:stale`) → `Activity.track("backoffice.action.<key>", reason:)` em volta do perform (ou sem transação) → `result`. Com `with:` (integração `lucid_case`): mapeia campos → attributes, erros de `validates` (`:invalid_attributes`) → campos, demais falhas → `result[:errors].first` (guards do lucid-case ≥ 0.3) ou `lucid_backoffice.actions.<key>.failures.<type>` ou genérica. Registro automático por `resources_path`/`actions_path`; chaves de rota só do registro.

**editable** no `Resource`: gera `Action` anônima `edit` com `field` por coluna (tipo do schema), `perform { record.update!(attrs) }` ou `with:`.

**Impersonação:** tabela `lucid_backoffice_impersonations` (`operator_type/id`, `tenant_identifier`, `user_type`, `user_id`, `reason`, `metadata` jsonb com guarda de payload, `started_at`, `expires_at`, `entered_at`, `ended_at`, `end_reason`); `activity_events.impersonation_id`. Ganchos: `impersonation.find_user ->(tenant, id)`, `sign_in ->(controller, user)`, `sign_out ->(controller)`, `entry_url ->(tenant)` (opcional), `return_url`, `duration` (30 min), `read_only_except` (rotas de leitura que usam POST, padrão vazio). Token: `message_verifier(:lucid_backoffice_impersonation)`, 60 s, uso único. `ImpersonationGuard` (concern do app): expiração, bloqueio de verbos, page view, `Current.actor` = operador. `ImpersonationMask` (concern de `ApplicationRecord`): `after_initialize` só com impersonação ativa e tabela fora da gem. Banner: partial `lucid/backoffice/impersonation/_banner` (sobrescrevível) com helper `lucid_backoffice_impersonation_banner`.

## PR 1 — núcleo da Action e dedução (branch: `feat/lucid-backoffice-actions-1`, base: `main`)
**Arquivos:** Create `lib/lucid/backoffice/action.rb`, `lib/lucid/backoffice/action/{field,preview,snapshot,registry,runner}.rb` — Test `test/action/dsl_test.rb`, `test/action/runner_test.rb` (dedução, stale, only_if, unavailable, permissão, transaction false, evento) — Docs `docs/specs/20261120210300_lucid_backoffice_actions_impersonation.md` (cópia)
**Valida:** `bundle exec rake test`

## PR 2 — telas, tipos de campo, danger e result (branch: `feat/lucid-backoffice-actions-2`, base: `feat/lucid-backoffice-actions-1`)
**Arquivos:** Create `app/controllers/lucid/backoffice/actions_controller.rb`, `app/views/lucid/backoffice/actions/{new,_field,_preview}.html.erb`, `app/views/lucid/backoffice/ui/_fields/*.html.erb` — Modify `config/routes.rb`, `app/views/lucid/backoffice/records/show.html.erb`, `app/views/lucid/backoffice/tenants/show.html.erb`, `app/assets/**` — Test `test/integration/actions_test.rb`
**Valida:** `bundle exec rake test && bundle exec rake assets:check`

## PR 3 — perform with Command e editable (branch: `feat/lucid-backoffice-actions-3`, base: `feat/lucid-backoffice-actions-2`)
**Arquivos:** Modify `lib/lucid/backoffice/integrations/lucid_case.rb`, `lib/lucid/backoffice/resource.rb`, `lib/lucid/backoffice/action/runner.rb` — Create `lib/lucid/backoffice/action/editable.rb` — Test `test/integrations/lucid_case_action_test.rb`, `test/action/editable_test.rb`
**Valida:** `bundle exec rake test`

## PR 4 — impersonação: modelo, token e telas (branch: `feat/lucid-backoffice-actions-4`, base: `feat/lucid-backoffice-actions-3`)
**Arquivos:** Create template de migration `create_lucid_backoffice_impersonations.rb.tt` (+ coluna `impersonation_id` em eventos), `app/models/lucid/backoffice/impersonation.rb`, `app/controllers/lucid/backoffice/impersonations_controller.rb`, `lib/lucid/backoffice/impersonation/{token,entry}.rb`, views — Modify `lib/lucid/backoffice/configuration.rb`, `config/routes.rb` — Test `test/impersonation/start_test.rb`, `test/impersonation/token_test.rb`
**Valida:** `bundle exec rake test`

## PR 5 — guarda, banner e máscara no app (branch: `feat/lucid-backoffice-actions-5`, base: `feat/lucid-backoffice-actions-4`)
**Arquivos:** Create `lib/lucid/backoffice/impersonation_guard.rb`, `lib/lucid/backoffice/impersonation_mask.rb`, `app/views/lucid/backoffice/impersonation/_banner.html.erb`, `app/helpers/lucid/backoffice/impersonation_helper.rb` — Test `test/impersonation/guard_test.rb` (verbos, expiração, page view, ator, end!), `test/impersonation/mask_test.rb`, `test/integration/impersonation_test.rb` (dummy com login próprio sem Devise)
**Valida:** `bundle exec rake test`

## PR 6 — gerador, docs e v0.2.0 (branch: `feat/lucid-backoffice-actions-6`, base: `feat/lucid-backoffice-actions-5`)
**Arquivos:** Modify `lib/generators/lucid/backoffice/install_generator.rb` (+ `rails g lucid:backoffice:action NAME`, `rails g lucid:backoffice:impersonation`), `docs/actions.md`, `docs/impersonation.md`, `README.md`, `CHANGELOG.md`, `lib/lucid/backoffice/version.rb` — Test `test/generators/action_generator_test.rb`
**Valida:** `bundle exec rake test` + tag `v0.2.0`

## SEQUENCE
1. #<pr1> — núcleo da Action
2. #<pr2> — telas e campos
3. #<pr3> — with Command e editable
4. #<pr4> — impersonação: modelo e token
5. #<pr5> — guarda, banner e máscara
6. #<pr6> — gerador, docs e v0.2.0
Merge in this order: #<pr1> #<pr2> #<pr3> #<pr4> #<pr5> #<pr6>

# definition of done

- [ ] Todo cenário de "acceptance criteria" foi validado (automatizado ou verificado com comando exato)
- [ ] Testes automáticos passando — suíte verde, não só a parte nova (CI)
- [ ] Toda task do "how" executada
- [ ] Documentação atualizada (`docs/actions.md`, `docs/impersonation.md`, `README.md`, `CHANGELOG.md`)
- [ ] Staging: `staging: none` (gem)
- [ ] Cada PR da sequência validado isoladamente (build e testes verdes sem os PRs seguintes)
- [ ] Último PR liga a funcionalidade e remove código temporário (tag `v0.2.0`)
- [ ] Ação mínima com dedução, motivo e evento (`test/action/runner_test.rb`)
- [ ] Stale, unavailable, only_if, preview própria, alvos tenant/global (`test/action/*`)
- [ ] danger high, transaction false, result, tipos de campo, 403 (`test/integration/actions_test.rb`)
- [ ] with Command: validações nos campos, mensagem do guard (`result[:errors]`) e fallback i18n, dois eventos com mesmo request_id (`test/integrations/lucid_case_action_test.rb`)
- [ ] editable só com campos declarados, com e sem with: (`test/action/editable_test.rb`)
- [ ] Impersonação: início, token de uso único, 404 inválido (`test/impersonation/*`)
- [ ] Somente leitura, banner, page view, expiração, replaced, end!, ator (`test/impersonation/guard_test.rb`)
- [ ] Máscara em memória e readonly (`test/impersonation/mask_test.rb`)

## documentation

- Repo da gem: `docs/actions.md`, `docs/impersonation.md`, `README.md`, `CHANGELOG.md`, cópia desta spec.
