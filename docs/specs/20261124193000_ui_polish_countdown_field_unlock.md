---
title: Acabamento visual, contador da revelação e liberação de campo para edição
status: proposed
created: 2026-11-24
updated: 2026-11-24
owner: "@oporpino"
certainty: high
---

# Acabamento visual, contador da revelação e liberação de campo para edição

> **TLDR**: a gem 0.5.0 fecha o redesign do painel (PR #46, sidebar sem cara de template, busca e filtro profissionais), troca "Revelado até HH:MM" por um contador regressivo que mascara de novo sozinho no fim do prazo, e tira os formulários da dependência do olho: cada campo mascarado é liberado um a um ("Liberar edição"), com evento e sem motivo. O luneta sobe para a v0.5.0.

Decisões: `docs/adr/0002-unlock-masked-field-without-reason.md`. Glossário: `docs/CONTEXT.md` (Locked field, Unlocked field, Reveal deadline). Base visual: PR #46 (`feat/ui-refresh`), inspirado em `~/workspace/brazza.tech/site`.

# what

Como operador do painel, quero uma interface com acabamento profissional, ver quanto tempo resta da revelação e corrigir um campo mascarado sem revelar o contexto inteiro, para operar com clareza e expondo só o necessário.

## out of scope

- Sincronizar o contador entre abas: cada aba conta a partir do que o servidor informou ao montar a página. Encerrar numa aba não atualiza as outras; o servidor continua sendo a fonte da verdade.
- Mudar o título da aba do navegador com o contador.
- Gravar valores (antes/depois) no rastro de atividade: só nomes de campos, como hoje.
- Pedir motivo para liberar um campo (ADR 0002).
- Borrar ou travar formulários no fim do prazo: o prazo só afeta o que é exibido.
- Marcar como revelado o texto de busca digitado pelo operador; só chips de filtro são marcados.
- Tema claro e novos tokens de tema.
- Feature flag: não há (ver `# how`).

## acceptance criteria

    Cenário: item selecionado da sidebar sem borda nem barra
      Dado o operador em "/backoffice/data/accounts"
      Quando a página carrega
      Então o link "accounts" da sidebar tem aria-current="page"
      E o CSS do item atual define só cor do texto e fundo (sem border-color, sem box-shadow e sem a cor de destaque)
      E o título "Dados" da sidebar usa a fonte sans, sem uppercase em mono

    Cenário: nome de tabela longo cabe na sidebar
      Dado uma tabela "active_storage_variant_records"
      Quando a sidebar é exibida
      Então o link mostra o nome cortado com reticências
      E o atributo title do link é "active_storage_variant_records"

    Cenário: popover de filtro com rótulos
      Dado o operador numa lista de tabela
      Quando ele abre "+ Filtro"
      Então o popover mostra os rótulos visíveis "Coluna" e "Valor", ligados aos campos por for/id
      E o botão de envio do popover diz "Aplicar filtro"

    Cenário: busca envia com Enter
      Dado o operador numa lista de tabela
      Quando ele digita no campo de busca e aperta Enter
      Então a busca é enviada (o campo e o botão "Buscar" estão no mesmo form)
      E o campo de busca exibe um ícone de lupa

    Cenário: contador parte dos segundos informados pelo servidor
      Dado o operador com revelações ativas que expiram em 10 e em 14 minutos
      Quando a página carrega
      Então o selo do olho tem data-lb-remaining igual aos segundos até a expiração mais próxima (600, com tolerância de 2s)
      E o title do selo é "Revelado até HH:MM"
      E o texto do selo, sem JavaScript, é "Revelado até HH:MM"
      E com JavaScript o texto passa a "Revelado · 09:59" e decresce a cada segundo

    Cenário: último minuto em âmbar
      Dado o contador com 60 segundos ou menos
      Então o selo recebe a classe lb-eye-warn e a cor --lb-warn

    Cenário: fim do prazo com a página limpa mascara de novo
      Dado o contador chegando a zero e nenhum formulário da página editado
      Quando chega a zero
      Então o navegador envia o form DELETE /reveals do próprio selo
      E o servidor redireciona de volta sem aviso
      E o selo volta a "Dados mascarados" e os valores aparecem mascarados

    Cenário: fim do prazo com formulário editado não perde o que foi digitado
      Dado o contador chegando a zero e um campo de formulário com valor diferente do inicial
      Quando chega a zero
      Então a página não recarrega
      E o selo mostra "Expirado" em vermelho (classe lb-eye-expired)
      E todo elemento com data-lb-revealed fica borrado e sem seleção (classe lb-expired no <html>)
      Quando o operador clica no selo
      Então o form DELETE /reveals é enviado e a página volta mascarada, sem aviso

    Cenário alternativo: o motivo do diálogo de revelar não conta como edição
      Dado o diálogo de revelar com texto no motivo
      Quando o contador chega a zero
      Então a página é tratada como limpa

    Cenário: encerrar com revelação ativa mantém o aviso
      Dado o operador com revelação ativa
      Quando ele clica em "Encerrar"
      Então as revelações são encerradas e o aviso "Revelação encerrada" aparece, como hoje

    Cenário: valores revelados são marcados pelo servidor
      Dado a categoria "contact" revelada e uma tabela com colunas public, contact e documents
      Quando a lista e o detalhe do registro são exibidos
      Então as células de contact têm data-lb-revealed
      E as células public não têm data-lb-revealed
      E as células de documents têm lb-masked e não têm data-lb-revealed
      E um link de chave estrangeira sobre coluna revelada também tem data-lb-revealed

    Cenário: prévia de Ação usa o estado real do valor
      Dado uma Ação que muda um campo contact com a categoria revelada e outro documents sem revelar
      Quando a prévia é exibida
      Então os valores de contact têm data-lb-revealed e não têm lb-masked
      E os valores de documents têm lb-masked
      E valores de colunas public não têm nenhum dos dois

    Cenário: chip de filtro sobre coluna revelada
      Dado a categoria "contact" revelada e um filtro em "email"
      Quando a lista é exibida
      Então o chip "email = ..." tem data-lb-revealed
      E um chip sobre coluna public não tem

    Cenário: campo mascarado começa travado mesmo com revelação ativa
      Dado a categoria "contact" revelada e a Ação edit_accounts com o campo email (contact)
      Quando o operador abre o formulário
      Então o campo email aparece como pontos, desabilitado, sem name e sem o valor no HTML
      E ao lado há o botão "Liberar edição"

    Cenário: liberar um campo mascarado lê o valor e deixa evento
      Dado o operador com :reveal para "contact" e o formulário de edit_accounts aberto
      Quando ele clica em "Liberar edição" no email
      Então o navegador faz POST /actions/edit_accounts/fields/email/unlock com o token CSRF
      E a resposta é JSON com o valor atual, Cache-Control no-store
      E um evento "backoffice.field.unlock" é gravado com tabela, coluna, id do registro e Ação, sem valor e sem motivo
      E o campo vira editável com o valor e com um hidden "unlocked[]" = "email"

    Cenário alternativo: liberar sem permissão de revelar
      Dado o operador sem :reveal para "contact"
      Quando ele faz POST /actions/edit_accounts/fields/email/unlock
      Então a resposta é 403 sem valor e nenhum evento "backoffice.field.unlock" é gravado
      E o formulário não mostra o botão "Liberar edição" para esse campo

    Cenário alternativo: coluna secret ou oculta é só escrita
      Dado um campo sobre coluna secret ou listada em hide
      Quando o formulário é exibido
      Então o botão diz "Definir novo valor"
      E o clique esvazia o campo, habilita a digitação e adiciona "unlocked[]" sem chamar o servidor
      E POST /actions/:key/fields/:field/unlock para esse campo responde 403 sem valor e sem evento

    Cenário alternativo: liberar campo que não é travado
      Dado um campo sobre coluna public
      Quando alguém faz POST /actions/:key/fields/:field/unlock para ele
      Então a resposta é 404

    Cenário: ao sair do campo liberado ele volta a mostrar pontos
      Dado um campo liberado e focado
      Quando o operador sai do campo
      Então o valor aparece como pontos (o valor continua no campo e é enviado)
      E um ícone de olho deixa ver o valor de novo

    Cenário: salvar um campo liberado
      Dado o email liberado e alterado
      Quando o operador executa a Ação com motivo
      Então o registro passa a ter o novo email
      E o evento da Ação grava "email" em changed_fields e nenhum valor

    Cenário alternativo: envio forjado de campo travado é descartado
      Dado um POST da Ação com fields[email] e sem unlocked[]
      Então o servidor usa o valor atual do registro, como hoje

    Cenário alternativo: unlocked forjado sem permissão é descartado
      Dado o operador sem :reveal para "contact"
      Quando ele envia fields[email] com unlocked[]=email
      Então o servidor usa o valor atual do registro

    Cenário alternativo: novo valor de secret em branco mantém o atual
      Dado um campo secret liberado e deixado em branco
      Quando a Ação é executada
      Então o servidor usa o valor atual do registro

    Cenário alternativo: sem JavaScript
      Dado o navegador sem JavaScript
      Então o selo mostra "Revelado até HH:MM" e o encerramento manual funciona
      E os campos travados continuam travados e o formulário executa com os valores atuais

    Cenário: luneta na v0.5.0
      Dado o luneta com lucid-backoffice tag v0.5.0
      Quando a suíte roda e o merge na main sobe staging
      Então make core.test passa e as rotas do painel respondem no ping de staging

# why

- **Aparência**: o formulário "Novo usuário", a visão do tenant, a sidebar (item atual em card com barra lima) e a barra de busca/filtro (campos de tamanhos diferentes, popover sem rótulo) parecem rascunho. É a tela que o time de suporte usa o dia todo.
- **Prazo invisível**: "Revelado até 19:17" obriga a fazer conta, e quando o prazo passa os dados continuam em claro na tela até a próxima navegação. A revelação promete prazo e a tela não cumpre.
- **Exposição desproporcional para editar**: na 0.4.0 um campo mascarado só destrava revelando todas as categorias do contexto. Para corrigir um e-mail, o operador abre CPF, telefone e tudo mais por 15 minutos. Liberar campo a campo expõe só o que a edição precisa, com rastro (ADR 0002).

# how

Repos: gem em `~/workspace/br4zz4/lucid-backoffice` (suíte `bundle exec rake test`), luneta em `~/workspace/brazza.tech/lunetamagica`, app em `modules/core/code` (suíte `make core.test`, staging `merge-main` em `https://staging.lunetamagica.com.br`). A gem não declara staging (`staging: none`).

**Feature flag:** não. As mudanças visuais e o contador são aditivos; a liberação de campo substitui o destravamento pelo olho num release minor (0.5.0) com CHANGELOG, e o comportamento sem JavaScript continua seguro (campo travado usa o valor atual).

**Telas** (gem; o ping roda no luneta): sidebar e topbar em todas as páginas; lista e detalhe de tabela (`/backoffice/data/:table`, `/backoffice/data/:table/:id`, e as variantes `/backoffice/tenants/:tenant_id/...`); formulário de Ação (`/backoffice/actions/:action_key/new`); visão do tenant (`/backoffice/tenants/:tenant_id`).

**Convenções desta spec:**
- "Valor revelado" = valor exibido em claro porque a categoria dele (não `public`) está revelada. A marca é o atributo `data-lb-revealed` e sai sempre do servidor, do mesmo ponto que decide mascarar.
- O CSS do borrão é uma regra única: `.lb-expired [data-lb-revealed] { filter: blur(6px); user-select: none; pointer-events: none; }`. O JavaScript só liga `lb-expired` no `<html>`.
- "Formulário editado": qualquer `input`, `textarea` ou `select` de um `form` da página, fora de `.lb-reveal-form`, que não seja `hidden`, `submit` ou `button`, cujo `value` difira de `defaultValue`, `checked` de `defaultChecked`, ou alguma `option.selected` de `defaultSelected`. Implementado numa função `lbDirty(document)` no `lucid_backoffice.js`.
- JavaScript em `app/assets/lucid_backoffice.js`, no estilo existente (ES5, `DOMContentLoaded`, sem dependências). Cada comportamento é um bloco próprio, ligado por atributo `data-lb-*`.

## PR 0 — Redesign de CSS (já aberto: #46, branch `feat/ui-refresh`, base `main`)
**Entrega:** formulários em card, seções em card, foco com anel, select com chevron, fundo com brilho violeta, vidro na sidebar/topbar.
**Passos:** conferir CI verde do #46 e mergear (merge normal). As branches abaixo partem da `main` já com ele.
**Valida:** `gh pr checks 46` verde; `git log origin/main --oneline -3` mostra o merge.

## PR 1 — Sidebar e barra de busca/filtro (branch: `feat/ui-polish-1`, base: `main`)
**Entrega:** acabamento visual de navegação e consulta, sem mudança de comportamento.
**Arquivos:** Modify `app/assets/lucid_backoffice.css`, `app/views/lucid/backoffice/shared/_sidebar.html.erb`, `app/views/lucid/backoffice/ui/_query_bar.html.erb`, `config/locales/pt-BR.yml`, `config/locales/en.yml` — Test `test/integration/layout_test.rb`, `test/integration/data_test.rb`.
**Passos:**
1. Testes (tester) que falham: link de tabela da sidebar com `title` igual ao nome; popover com `<label for>` "Coluna"/"Valor" e submit "Aplicar filtro"; campo de busca e botão "Buscar" no mesmo form com um `svg` de lupa.
2. `_sidebar.html.erb`: `title="<%= table %>"` nos links `.lb-nav-table`.
3. CSS da sidebar (substitui as regras de item atual e hover):
   - `.lb .lb-sidebar .lb-nav-main a, .lb .lb-sidebar .lb-nav-data a`: `padding: .38rem .6rem; border: 0; border-radius: 6px; font-size: .85rem; line-height: 1.35;`, cor `--lb-muted`.
   - hover: `background: rgb(255 255 255 / .04); color: var(--lb-text);`, sem borda.
   - atual (`[aria-current="page"]`): `background: rgb(255 255 255 / .06); color: var(--lb-text);`, sem `border-color`, sem `box-shadow`.
   - `.lb-nav-data h3`: `font-family: var(--lb-font-sans); font-size: .69rem; font-weight: 500; letter-spacing: .06em; text-transform: uppercase; color: var(--lb-muted);` (sans, não mono em negrito).
   - `.lb-nav-table`: mono `.78rem`, `overflow: hidden; text-overflow: ellipsis; white-space: nowrap; display: block`.
   - remover a regra antiga `box-shadow: inset 2px 0 0 var(--lb-accent)` e as `border-color` de hover/atual.
4. `_query_bar.html.erb`:
   - busca: envolver o `search_field_tag` num `<label class="lb-search">` com um `svg` de lupa (aria-hidden) posicionado dentro do campo; o botão "Buscar" ganha `lb-button lb-button-quiet` (contorno, sem preenchimento lima).
   - popover: `select_tag :filter_column` e `text_field_tag :filter_value` com ids `lb-filter-column`/`lb-filter-value` e `<label for>` visíveis com `t("lucid_backoffice.filter_column")`/`filter_value` (os `aria-label` saem); submit `t("lucid_backoffice.apply_filter")`; o form `.lb-menu-list` vira coluna (`display: grid; gap: .75rem; min-width: 18rem; padding: 1rem`) com campos `width: 100%`.
   - chips: `.lb-chip` no estilo de `.lb-tag` (mono `.72rem`, fundo `rgb(255 255 255 / .04)`), `.lb-chip-remove` com área de clique de 1.25rem e `:hover` na cor do texto.
5. CSS: `.lb-button-quiet { background: transparent; color: var(--lb-text); border-color: var(--lb-border); box-shadow: none; }` e hover com `border-color: rgb(255 255 255 / .3)`; `.lb-search` com `position: relative` e `padding-left: 2.4rem` no input.
6. Locales: `apply_filter` (pt-BR "Aplicar filtro", en "Apply filter").
7. Commit `feat: polish sidebar and query bar`.
**Pronto para prod:** só markup/CSS; mesmos forms, mesmos parâmetros.
**Valida:** `bundle exec rake test`; screenshot com Chrome headless de uma lista com o popover aberto (`<details open>`) e de uma página com item atual na sidebar.

## PR 2 — Marca de valor revelado e fim de prazo sem aviso (branch: `feat/ui-polish-2`, base: `feat/ui-polish-1`)
**Entrega:** o servidor marca valores revelados; `DELETE /reveals` sem revelação ativa redireciona sem aviso. Nenhum JavaScript novo ainda.
**Arquivos:** Modify `lib/lucid/backoffice/records.rb`, `app/views/lucid/backoffice/ui/_value.html.erb`, `lib/lucid/backoffice/action/preview.rb`, `app/views/lucid/backoffice/actions/_preview.html.erb`, `app/views/lucid/backoffice/ui/_query_bar.html.erb`, `app/controllers/lucid/backoffice/reveals_controller.rb`, `app/assets/lucid_backoffice.css` — Test `test/integration/data_test.rb`, `test/integration/actions_test.rb`, `test/integration/reveal_eye_test.rb`, `test/lucid/backoffice/action/preview_test.rb` (criar se não existir).
**Passos:**
1. Testes que falham para os cenários "valores revelados são marcados pelo servidor", "prévia de Ação usa o estado real do valor", "chip de filtro sobre coluna revelada", "fim do prazo com a página limpa" (DELETE sem ativas → redirect sem `flash[:notice]`) e "encerrar com revelação ativa mantém o aviso".
2. `Records::Cell`: novo atributo `revealed` (default `false`); em `cells`, `revealed: open && column.category != Classification::PUBLIC`.
3. `_value.html.erb`: `data-lb-revealed` quando `cell.revealed`, no `<a>` e no `<span>`.
4. `Preview::Change`: novo atributo `revealed`; em `masked`, `revealed: open && c.category != Classification::PUBLIC`; `change` cria com `revealed: false`.
5. `_preview.html.erb`: `lb-masked` só quando o valor está mascarado (`!change.revealed && change.category != public`); `data-lb-revealed` quando `change.revealed`.
6. `_query_bar.html.erb`: o `<span>` do chip recebe `data-lb-revealed` quando a coluna do filtro não é `public` (a categoria vem de `usable`, já filtrado por visível).
7. `RevealsController#destroy_all`: `ended = Reveal.revoke_all(...)`; `notice` só quando `ended.any?`.
8. CSS: a regra única do borrão (ver convenções).
9. Commit `feat: mark revealed values and mask silently on expiry`.
**Pronto para prod:** atributos novos sem efeito visual até alguém ligar `lb-expired`; o DELETE muda só o aviso no caso sem revelação ativa.
**Valida:** `bundle exec rake test`.

## PR 3 — Contador regressivo do olho (branch: `feat/ui-polish-3`, base: `feat/ui-polish-2`)
**Entrega:** selo com `mm:ss`, âmbar no último minuto, DELETE automático com página limpa, "Expirado" com borrão quando há formulário editado.
**Arquivos:** Modify `app/views/lucid/backoffice/ui/_reveal_eye.html.erb`, `app/assets/lucid_backoffice.js`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml` — Test `test/integration/reveal_eye_test.rb`.
**Passos:**
1. Testes que falham: `data-lb-remaining` = `(expires_at.min - Time.current).ceil` (tolerância 2s); `title` = "Revelado até HH:MM"; texto sem JS segue "Revelado até HH:MM"; `data-lb-label-running`, `data-lb-label-expired` com os textos traduzidos; chaves novas nos dois locales.
2. `_reveal_eye.html.erb`, ramo ativo: o `button_to` ganha `data: { lb_countdown: true, lb_remaining: <segundos>, lb_label_running: t("lucid_backoffice.revealed_running"), lb_label_expired: t("lucid_backoffice.reveal_expired") }` e `title` "Revelado até HH:MM"; o `<span>` do texto ganha `data-lb-countdown-label`.
3. JS (bloco `[data-lb-countdown]`):
   - `deadline = performance.now() + remaining * 1000`; `tick()` calcula `left = max(0, ceil((deadline - performance.now()) / 1000))`, escreve `label_running` com `%{time}` = `mm:ss` (minutos sem limite, segundos com 2 dígitos), alterna `lb-eye-warn` quando `left <= 60`.
   - `setInterval(tick, 1000)` e `tick()` também em `visibilitychange`, para corrigir após a aba voltar do segundo plano.
   - em `left === 0`: para o intervalo; se `!lbDirty(document)`, `form.requestSubmit()` no form do próprio selo; senão, `document.documentElement.classList.add("lb-expired")`, selo com `lb-eye-expired` (remove `lb-eye-on` e `lb-eye-warn`), texto `label_expired`, e esconde `.lb-eye-end`.
   - `lbDirty(root)` conforme as convenções.
4. CSS: `.lb-eye-warn` (cor, borda e fundo com `--lb-warn`, como `.lb-eye-on`), `.lb-eye-expired` (idem com `--lb-danger`); `font-variant-numeric: tabular-nums` no texto do selo para o número não pular.
5. Locales: `revealed_running` (pt-BR "Revelado · %{time}", en "Revealed · %{time}"), `reveal_expired` (pt-BR "Expirado", en "Expired").
6. Verificação manual no app dummy com `config.reveal_duration = 70`: contar, ver âmbar aos 60s, ver o DELETE em zero com página limpa; repetir com texto digitado na busca e ver "Expirado" vermelho e células borradas; clicar e ver a página mascarada sem aviso.
7. Commit `feat: reveal countdown with silent re-mask`.
**Pronto para prod:** sem JS o selo é o de hoje; com JS o caminho de fim é o mesmo DELETE já existente.
**Valida:** `bundle exec rake test` e a verificação manual do passo 6.

## PR 4 — Liberar edição campo a campo (branch: `feat/ui-polish-4`, base: `feat/ui-polish-3`)
**Entrega:** formulários independentes do olho; "Liberar edição" (leitura com evento) e "Definir novo valor" (só escrita); o servidor aceita valor de campo travado só quando liberado e permitido.
**Arquivos:** Modify `config/routes.rb`, `app/controllers/lucid/backoffice/actions_controller.rb`, `lib/lucid/backoffice/action.rb`, `lib/lucid/backoffice/action/runner.rb`, `app/views/lucid/backoffice/actions/_field.html.erb`, `app/assets/lucid_backoffice.js`, `app/assets/lucid_backoffice.css`, `config/locales/pt-BR.yml`, `config/locales/en.yml` — Test `test/integration/field_unlock_test.rb` (novo), `test/lucid/backoffice/action/field_test.rb`, `test/integration/editable_test.rb`, `test/integration/actions_test.rb`.
**Passos:**
1. Testes que falham para todos os cenários de formulário: travado mesmo com revelação ativa; unlock lê valor com `no-store` e grava `backoffice.field.unlock`; 403 sem `:reveal`; secret/hide com "Definir novo valor" e 403 no endpoint; 404 para campo não travado; salvar com `unlocked[]`; forjado sem `unlocked[]`; `unlocked[]` sem permissão; secret em branco mantém o atual; `changed_fields` com o nome e sem valor. Ajustar os testes da 0.4.0 que esperavam o campo destravado pela revelação (`field_test.rb` ~ linhas 401-550, `editable_test.rb`) para o novo contrato.
2. `Action`:
   - `locked_names` deixa de receber `revealed:`: trava todo campo de coluna do registro que não é `public` (inclui hidden).
   - `unlock_mode(name)` → `:read` (coluna mascarada não oculta), `:write` (oculta) ou `nil` (não travado).
   - `initial_values` sem `revealed:`; campo travado continua `Field::LOCKED`.
   - `with_locked_current(params, unlocked: [], operator:)`: para cada travado, usa o valor enviado só se `name` está em `unlocked`, o valor enviado não está em branco quando `unlock_mode == :write`, e, para `:read`, `Authorization.allowed?(operator, :reveal, { tenant: tenant, category: category })`; senão usa `record.public_send(name)`.
3. `Runner.call`: troca `revealed:` por `unlocked:` na chamada de `with_locked_current` (passa `operator`); `revealed` continua só para a prévia.
4. Rota `post "actions/:action_key/fields/:field/unlock", to: "actions#unlock", as: :unlock_action_field`.
5. `ActionsController#unlock`: `authorize!(@action_class.permission, context)`; acha o registro; `mode = action.unlock_mode(field)`; `nil` → 404; `:write` → 403; `:read` sem `:reveal` da categoria → 403; senão grava `Activity.record(name: "backoffice.field.unlock", subjects: [{ "type" => "Table", "name" => table, "id" => record.id }], payload: { column: field, action: key })` e responde `render json: { value: }` com `Cache-Control: no-store`. Se o evento falha, nada é devolvido (fail closed, como o resto). `new`/`prepare_preview`/`render_form` deixam de passar `revealed:` para `initial_values`/`locked_names`; `field_params` aceita `unlocked: []`.
6. `_field.html.erb`, campo travado: um wrapper `.lb-locked-field` com `data-lb-unlock` (`read` ou `write`), `data-lb-unlock-url` (só em `read`, com `record_id` e `tenant_id`), o input de pontos desabilitado e sem `name`, um `<template>` com o controle real (o mesmo `case field.type` de hoje, vazio, com `name="fields[...]"`) e um botão `type="button"` com ícone de lápis e o texto `unlock_field` ("Liberar edição") ou `set_new_value` ("Definir novo valor"). Em `read`, o botão só aparece se o operador tem `:reveal` da categoria.
7. JS (bloco `[data-lb-unlock]`):
   - `read`: `fetch(url, { method: "POST", headers: { "X-CSRF-Token": <meta csrf-token>, "Accept": "application/json" }, credentials: "same-origin" })`; com 200, troca o input de pontos pelo controle do `<template>` com o valor, adiciona `<input type=hidden name="unlocked[]" value="<campo>">` e foca; erro → mensagem `unlock_failed` ao lado do botão, campo segue travado.
   - `write`: troca pelo controle vazio, adiciona o hidden e foca, sem rede.
   - depois de liberado: em `focusout` do wrapper, adiciona `lb-concealed` (uma camada de pontos sobre o controle, `position: absolute`, cobre texto, select, data e textarea); um botão de olho e o clique na camada removem `lb-concealed` e focam o controle. O valor nunca sai do controle.
8. CSS: `.lb-locked-field` (linha com campo e botão), `.lb-unlock` (botão discreto como `.lb-button-quiet`, ícone de 1rem), `.lb-concealed` e a camada de pontos.
9. Locales: `unlock_field`, `set_new_value`, `unlock_failed`, `show_value`.
10. Commit `feat: unlock locked fields one at a time`.
**Pronto para prod:** sem JS o campo fica travado e o servidor usa o valor atual; envio sem `unlocked[]` se comporta como na 0.4.0.
**Valida:** `bundle exec rake test`; manual no dummy: liberar, sair do campo (pontos), olho (valor), salvar, conferir o evento em `/backoffice/activity`.

## PR 5 — Release 0.5.0 (branch: `feat/ui-polish-5`, base: `feat/ui-polish-4`)
**Entrega:** versão, CHANGELOG e documentação.
**Arquivos:** Modify `lib/lucid/backoffice/version.rb` (`0.5.0`), `CHANGELOG.md`, `docs/security.md`, `docs/masking-and-reveals.md`, `docs/actions.md`, `README.md` (se citar o destravamento pelo olho).
**Passos:**
1. CHANGELOG `## 0.5.0`: redesign (PR #46), sidebar e busca/filtro, contador regressivo com re-mascaramento silencioso, marca `data-lb-revealed`, "Liberar edição"/"Definir novo valor" com evento `backoffice.field.unlock` (ADR 0002), e a quebra: revelar não destrava mais campos de formulário; `Action#locked_names`/`initial_values` sem `revealed:`; `with_locked_current` com `unlocked:`.
2. `security.md`: troca "A field over a masked column is locked in Action forms and its submitted value is discarded" pela regra nova; acrescenta a rota `POST /actions/:action_key/fields/:field/unlock` à lista de rotas não-GET.
3. `masking-and-reveals.md`: contador, fim de prazo (DELETE silencioso, borrão com formulário editado), formulários independentes do olho.
4. `actions.md`: campos travados e liberação.
5. Commit `chore: release 0.5.0`. Depois do merge de toda a pilha na `main`: `git tag v0.5.0 && git push origin v0.5.0`.
**Pronto para prod:** só docs e versão.
**Valida:** `bundle exec rake test`; `git ls-remote --tags origin v0.5.0` mostra a tag.

## PR 6 — Luneta na v0.5.0 (repo luneta, branch: `chore/lucid-backoffice-0-5-0`, base: `main`, depois da tag)
**Entrega:** luneta usando a 0.5.0.
**Arquivos:** Modify `modules/core/code/Gemfile` (linha 152: `tag: 'v0.5.0'`), `modules/core/code/Gemfile.lock`; testes do luneta que dependam de campo destravado pela revelação, se houver (tester).
**Passos:** `bundle update lucid-backoffice` em `modules/core/code`; `make core.test`; commit `chore: bump lucid-backoffice to 0.5.0`; PR, CI verde, merge (staging sobe pela `main`); ping.
**Pronto para prod:** a gem já está taggeada e testada; o luneta só troca a versão.
**Valida:** `make core.test`; ping em staging (abaixo).

**Ping em staging (luneta)**, após o deploy da `main`, com `curl -sS -o /dev/null -w "%{http_code}" --retry 3 --retry-delay 2 https://staging.lunetamagica.com.br<rota>`: `/up` (200), `/backoffice` , `/backoffice/data/users`, `/backoffice/data/organizations`, `/backoffice/actions/create_users/new` (302 para o login = ok, exige auth).

## SEQUENCE
1. #46 — Redesign de CSS (já aberto)
2. #<pr1> — Sidebar e barra de busca/filtro
3. #<pr2> — Marca de valor revelado e fim de prazo sem aviso
4. #<pr3> — Contador regressivo do olho
5. #<pr4> — Liberar edição campo a campo
6. #<pr5> — Release 0.5.0 (tag v0.5.0 após o merge)
7. #<pr6> — Luneta na v0.5.0 (repo luneta)
Merge in this order: #46 #<pr1> #<pr2> #<pr3> #<pr4> #<pr5> #<pr6>

# definition of done

- [ ] Todo cenário de "acceptance criteria" foi validado (automatizado ou verificado com comando exato)
- [ ] Testes automáticos passando — suíte verde, não só a parte nova (`bundle exec rake test` na gem; `make core.test` no luneta)
- [ ] Toda task do "how" executada
- [ ] Documentação atualizada (`docs/security.md`, `docs/masking-and-reveals.md`, `docs/actions.md`, `CHANGELOG.md`; `docs/CONTEXT.md` e ADR 0002 já nesta spec)
- [ ] Staging: merge na main do luneta feito e todas as rotas do ping respondem (gem: `staging: none`)
- [ ] Cada PR da sequência validado isoladamente (build e testes verdes sem os PRs seguintes)
- [ ] Último PR liga a funcionalidade e remove código temporário (PR 6 sobe o luneta; nenhum código temporário na gem)
- [ ] PR #46 mergeado na `main` com CI verde
- [ ] Cenário "item selecionado da sidebar sem borda nem barra": teste de `aria-current` em `layout_test.rb` e `grep` no CSS sem `box-shadow`/`border-color` nas regras de item atual; screenshot headless conferido
- [ ] Cenário "nome de tabela longo cabe na sidebar": teste do `title` em `layout_test.rb`
- [ ] Cenário "popover de filtro com rótulos": teste em `data_test.rb` (labels com `for` e submit "Aplicar filtro")
- [ ] Cenário "busca envia com Enter": teste em `data_test.rb` (campo e botão no mesmo form, `svg` presente)
- [ ] Cenário "contador parte dos segundos informados pelo servidor": teste de `data-lb-remaining`, `title` e texto sem JS em `reveal_eye_test.rb`; contagem verificada no dummy
- [ ] Cenário "último minuto em âmbar": verificado no dummy com `reveal_duration = 70`
- [ ] Cenário "fim do prazo com a página limpa": teste do DELETE sem ativas sem `flash[:notice]` em `reveal_eye_test.rb`; envio automático verificado no dummy
- [ ] Cenário "fim do prazo com formulário editado": verificado no dummy (selo "Expirado" vermelho, células borradas, clique mascara sem aviso)
- [ ] Cenário "o motivo do diálogo de revelar não conta como edição": verificado no dummy
- [ ] Cenário "encerrar com revelação ativa mantém o aviso": teste em `reveal_eye_test.rb`
- [ ] Cenário "valores revelados são marcados pelo servidor": testes em `data_test.rb` (lista, detalhe e link de FK)
- [ ] Cenário "prévia de Ação usa o estado real do valor": testes em `actions_test.rb` e `preview_test.rb`
- [ ] Cenário "chip de filtro sobre coluna revelada": teste em `data_test.rb`
- [ ] Cenário "campo mascarado começa travado mesmo com revelação ativa": teste em `field_unlock_test.rb` (sem `name`, sem valor no HTML, botão presente)
- [ ] Cenário "liberar um campo mascarado lê o valor e deixa evento": teste em `field_unlock_test.rb` (JSON, `no-store`, evento sem valor e sem motivo); liberação verificada no dummy
- [ ] Cenário "liberar sem permissão de revelar": teste em `field_unlock_test.rb` (403, sem evento, sem botão)
- [ ] Cenário "coluna secret ou oculta é só escrita": teste em `field_unlock_test.rb` (texto do botão, 403 no endpoint, sem evento); verificado no dummy
- [ ] Cenário "liberar campo que não é travado": teste em `field_unlock_test.rb` (404)
- [ ] Cenário "ao sair do campo liberado ele volta a mostrar pontos": verificado no dummy (pontos, olho, valor enviado)
- [ ] Cenário "salvar um campo liberado": teste em `field_unlock_test.rb` (registro atualizado, `changed_fields` com "email", sem valor no evento)
- [ ] Cenário "envio forjado de campo travado é descartado": teste em `field_unlock_test.rb`
- [ ] Cenário "unlocked forjado sem permissão é descartado": teste em `field_unlock_test.rb`
- [ ] Cenário "novo valor de secret em branco mantém o atual": teste em `field_test.rb`
- [ ] Cenário "sem JavaScript": testes de HTML (selo com texto do servidor, campo travado sem `name`) e execução da Ação sem `unlocked[]` em `field_unlock_test.rb`
- [ ] Cenário "luneta na v0.5.0": `make core.test` verde e tabela `rota | status | resultado` do ping de staging
- [ ] Tag `v0.5.0` publicada (`git ls-remote --tags origin v0.5.0`)
- [ ] Banner `FINISHED` impresso como última saída (`br4zz4:finish`, Step 7), só com todos os itens acima marcados

## documentation

- `docs/CONTEXT.md`: Locked field (revisado), Unlocked field e Reveal deadline (novos), já nesta spec.
- `docs/adr/0002-unlock-masked-field-without-reason.md`, já nesta spec.
- PR 5: `docs/security.md`, `docs/masking-and-reveals.md`, `docs/actions.md`, `CHANGELOG.md`, `README.md` se citar o destravamento pelo olho.
