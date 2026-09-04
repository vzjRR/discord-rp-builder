/* ── MangoNazlet counter menu ────────────────────────────────────
   Presentation only. Prices shown here are for the customer's benefit;
   the server prices every basket again from its own product table, so a
   rewritten menu can change what is asked for but never what is paid. */

(function () {
    'use strict';

    var state = {
        open: false,
        locale: {},
        products: [],
        stock: {},
        requireStock: true,
        payment: { cash: true, bank: true },
        maxPerCheckout: 10,
        category: 'all',
        basket: {},          // item -> quantity
        account: 'bank',
        busy: false
    };

    var el = {
        root: document.getElementById('root'),
        tagline: document.getElementById('tagline'),
        tabs: document.getElementById('tabs'),
        catalogue: document.getElementById('catalogue'),
        cartTitle: document.getElementById('cart-title'),
        lines: document.getElementById('lines'),
        cartEmpty: document.getElementById('cart-empty'),
        payLabel: document.getElementById('pay-label'),
        methods: document.getElementById('methods'),
        totalLabel: document.getElementById('total-label'),
        totalValue: document.getElementById('total-value'),
        checkout: document.getElementById('checkout'),
        close: document.getElementById('close')
    };

    /* ── helpers ─────────────────────────────────────────────── */

    function t(key, fallback) {
        var value = state.locale[key];
        return typeof value === 'string' && value.length ? value : (fallback || key);
    }

    function money(amount) {
        var n = Math.floor(Number(amount) || 0);
        return (t('currency', '$')) + n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    }

    function post(name, body) {
        return fetch('https://' + GetParentResourceName() + '/' + name, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {})
        }).then(function (r) { return r.json(); }).catch(function () { return { ok: false }; });
    }

    // FiveM injects this; the fallback keeps the page usable if opened directly.
    function GetParentResourceName() {
        return (typeof window.GetParentResourceName === 'function')
            ? window.GetParentResourceName()
            : 'mangonazlet';
    }

    function available(item) {
        if (!state.requireStock) return Infinity;
        var n = state.stock[item];
        return typeof n === 'number' ? n : 0;
    }

    /* ── rendering ───────────────────────────────────────────── */

    function categoryLabel(category) {
        // Categories are shown with their own locale strings where one exists,
        // otherwise a readable capitalisation of the raw category.
        var key = 'category_' + category;
        if (state.locale[key]) return state.locale[key];
        return category.charAt(0).toUpperCase() + category.slice(1);
    }

    function renderTabs() {
        var categories = [];
        state.products.forEach(function (p) {
            if (categories.indexOf(p.category) === -1) categories.push(p.category);
        });

        el.tabs.textContent = '';

        var all = ['all'].concat(categories);
        all.forEach(function (category) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'tab';
            button.setAttribute('role', 'tab');
            button.setAttribute('aria-selected', state.category === category ? 'true' : 'false');
            button.textContent = category === 'all' ? t('shop_all', 'All') : categoryLabel(category);
            button.addEventListener('click', function () {
                state.category = category;
                renderTabs();
                renderCatalogue();
            });
            el.tabs.appendChild(button);
        });
    }

    function renderCatalogue() {
        el.catalogue.textContent = '';

        var list = state.products.filter(function (p) {
            return state.category === 'all' || p.category === state.category;
        });

        list.forEach(function (product) {
            var stock = available(product.item);
            var inBasket = state.basket[product.item] || 0;
            var soldOut = state.requireStock && stock <= 0;
            var maxed = state.requireStock && inBasket >= stock;

            var card = document.createElement('button');
            card.type = 'button';
            card.className = 'card';
            card.disabled = soldOut || maxed || state.busy;

            var name = document.createElement('span');
            name.className = 'name';
            name.textContent = product.label;

            var desc = document.createElement('span');
            desc.className = 'desc';
            desc.textContent = product.desc || '';

            var row = document.createElement('span');
            row.className = 'row';

            var price = document.createElement('span');
            price.className = 'price';
            price.textContent = money(product.price);

            var stockTag = document.createElement('span');
            stockTag.className = 'stock' + (soldOut ? ' out' : '');
            if (!state.requireStock) {
                stockTag.textContent = '';
            } else if (soldOut) {
                stockTag.textContent = t('shop_sold_out', 'Sold out');
            } else {
                stockTag.textContent = t('shop_stock', 'In stock: %s').replace('%s', stock);
            }

            row.appendChild(price);
            row.appendChild(stockTag);

            card.appendChild(name);
            card.appendChild(desc);
            card.appendChild(row);

            card.addEventListener('click', function () { addToBasket(product); });
            el.catalogue.appendChild(card);
        });
    }

    function renderCart() {
        el.lines.textContent = '';

        var items = Object.keys(state.basket);
        var total = 0;

        items.forEach(function (item) {
            var product = findProduct(item);
            if (!product) return;

            var quantity = state.basket[item];
            var lineTotal = product.price * quantity;
            total += lineTotal;

            var li = document.createElement('li');
            li.className = 'line';

            var name = document.createElement('span');
            name.className = 'n';
            name.textContent = product.label;

            var price = document.createElement('span');
            price.className = 'p';
            price.textContent = money(lineTotal);

            var qty = document.createElement('span');
            qty.className = 'qty';

            var minus = document.createElement('button');
            minus.type = 'button';
            minus.textContent = '−';
            minus.setAttribute('aria-label', '-');
            minus.addEventListener('click', function () { setQuantity(item, quantity - 1); });

            var count = document.createElement('span');
            count.className = 'count';
            count.textContent = String(quantity);

            var plus = document.createElement('button');
            plus.type = 'button';
            plus.textContent = '+';
            plus.setAttribute('aria-label', '+');
            plus.addEventListener('click', function () { setQuantity(item, quantity + 1); });

            var drop = document.createElement('button');
            drop.type = 'button';
            drop.className = 'drop';
            drop.textContent = t('shop_remove', 'Remove');
            drop.addEventListener('click', function () { setQuantity(item, 0); });

            qty.appendChild(minus);
            qty.appendChild(count);
            qty.appendChild(plus);
            qty.appendChild(drop);

            li.appendChild(name);
            li.appendChild(price);
            li.appendChild(qty);
            el.lines.appendChild(li);
        });

        var empty = items.length === 0;
        el.cartEmpty.textContent = empty ? t('shop_empty_cart', 'Your cart is empty') : '';
        el.cartEmpty.classList.toggle('hidden', !empty);

        el.totalValue.textContent = money(total);
        el.checkout.disabled = empty || state.busy;
        el.checkout.classList.remove('done');
        el.checkout.textContent = t('shop_checkout', 'Checkout');
    }

    function renderMethods() {
        el.methods.textContent = '';

        var methods = [];
        if (state.payment.cash) methods.push({ id: 'cash', label: t('shop_pay_cash', 'Cash') });
        if (state.payment.bank) methods.push({ id: 'bank', label: t('shop_pay_bank', 'Card') });

        if (methods.length && methods.every(function (m) { return m.id !== state.account; })) {
            state.account = methods[0].id;
        }

        methods.forEach(function (method) {
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'method';
            button.setAttribute('role', 'radio');
            button.setAttribute('aria-checked', state.account === method.id ? 'true' : 'false');
            button.textContent = method.label;
            button.addEventListener('click', function () {
                state.account = method.id;
                renderMethods();
            });
            el.methods.appendChild(button);
        });
    }

    function renderStatic() {
        el.tagline.textContent = t('tagline', '');
        el.cartTitle.textContent = t('shop_cart', 'Cart');
        el.payLabel.textContent = t('shop_pay_method', 'Payment');
        el.totalLabel.textContent = t('shop_total', 'Total');
        el.close.setAttribute('aria-label', t('shop_close', 'Close'));
    }

    /* ── basket ──────────────────────────────────────────────── */

    function findProduct(item) {
        for (var i = 0; i < state.products.length; i++) {
            if (state.products[i].item === item) return state.products[i];
        }
        return null;
    }

    function basketUnits() {
        return Object.keys(state.basket).reduce(function (sum, item) {
            return sum + state.basket[item];
        }, 0);
    }

    function addToBasket(product) {
        if (state.busy) return;
        setQuantity(product.item, (state.basket[product.item] || 0) + 1);
    }

    function setQuantity(item, quantity) {
        if (state.busy) return;

        quantity = Math.floor(Number(quantity) || 0);

        if (quantity <= 0) {
            delete state.basket[item];
        } else {
            var stock = available(item);
            if (state.requireStock && quantity > stock) quantity = stock;

            var others = basketUnits() - (state.basket[item] || 0);
            if (others + quantity > state.maxPerCheckout) {
                quantity = Math.max(state.maxPerCheckout - others, 0);
            }

            if (quantity <= 0) { delete state.basket[item]; }
            else { state.basket[item] = quantity; }
        }

        renderCatalogue();
        renderCart();
    }

    /* ── actions ─────────────────────────────────────────────── */

    function close() {
        if (!state.open) return;
        state.open = false;
        state.basket = {};
        state.busy = false;
        el.root.classList.add('hidden');
        el.root.setAttribute('aria-hidden', 'true');
        post('close', {});
    }

    function checkout() {
        if (state.busy) return;

        var basket = Object.keys(state.basket).map(function (item) {
            return { item: item, quantity: state.basket[item] };
        });
        if (!basket.length) return;

        state.busy = true;
        el.checkout.disabled = true;

        post('checkout', { basket: basket, account: state.account }).then(function (result) {
            state.busy = false;

            if (result && result.ok) {
                el.checkout.classList.add('done');
                el.checkout.textContent = t('shop_thanks', 'Thank you!');
                // The Lua side closes the menu on success; this is just feedback.
                return;
            }

            renderCatalogue();
            renderCart();
        });
    }

    /* ── message pump ────────────────────────────────────────── */

    window.addEventListener('message', function (event) {
        var data = event.data;
        if (!data || typeof data.action !== 'string') return;

        if (data.action === 'open') {
            state.locale = data.locale || {};
            state.products = Array.isArray(data.products) ? data.products : [];
            state.stock = data.stock || {};
            state.requireStock = data.requireStock !== false;
            state.payment = data.payment || { cash: true, bank: true };
            state.maxPerCheckout = Number(data.maxPerCheckout) || 10;
            state.category = 'all';
            state.basket = {};
            state.busy = false;
            state.open = true;

            document.documentElement.setAttribute('dir', data.direction === 'rtl' ? 'rtl' : 'ltr');
            document.documentElement.setAttribute('lang', data.direction === 'rtl' ? 'ar' : 'en');

            if (data.theme) {
                var root = document.documentElement;
                Object.keys(data.theme).forEach(function (key) {
                    if (/^[a-z]+$/i.test(key) && typeof data.theme[key] === 'string') {
                        root.style.setProperty('--' + key, data.theme[key]);
                    }
                });
            }

            renderStatic();
            renderTabs();
            renderCatalogue();
            renderMethods();
            renderCart();

            el.root.classList.remove('hidden');
            el.root.setAttribute('aria-hidden', 'false');

        } else if (data.action === 'stock') {
            state.stock = data.stock || {};

            // Trim anything the shop just ran out of.
            Object.keys(state.basket).forEach(function (item) {
                var stock = available(item);
                if (state.requireStock && state.basket[item] > stock) {
                    if (stock <= 0) { delete state.basket[item]; }
                    else { state.basket[item] = stock; }
                }
            });

            if (state.open) {
                renderCatalogue();
                renderCart();
            }

        } else if (data.action === 'close') {
            state.open = false;
            state.basket = {};
            el.root.classList.add('hidden');
            el.root.setAttribute('aria-hidden', 'true');
        }
    });

    document.addEventListener('keydown', function (event) {
        if (!state.open) return;
        if (event.key === 'Escape') { event.preventDefault(); close(); }
    });

    el.close.addEventListener('click', close);
    el.checkout.addEventListener('click', checkout);
})();
