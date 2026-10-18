package app.storefront.data

/** No Firebase in this app (no `app/google-services.json`): no push either. */
fun pushTopic(): (suspend (String, Boolean) -> Unit)? = null
