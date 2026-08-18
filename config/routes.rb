Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "sessions#new"
  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"
  get "dashboard", to: "dashboard#index"
  get "reports", to: "reports#index"
  get "reports/export", to: "reports#export", as: :export_reports
  get "profile", to: "users#profile", as: :profile
  get "location_options/villages", to: "location_options#villages"
  get "location_options/shgs", to: "location_options#shgs"
  get "location_options/members", to: "location_options#members"
  resource :location_import, only: %i[new create]
  resource :location_export, only: :show

  soft_disable_routes = lambda do
    member { patch :disable }
  end

  resources :states, &soft_disable_routes
  resources :districts, &soft_disable_routes
  resources :blocks, &soft_disable_routes
  resources :villages, &soft_disable_routes
  resources :user_types, &soft_disable_routes
  resources :users do
    member do
      patch :reset_password
      patch :activate
      patch :disable
    end

    collection do
      get :export
      get :import, action: :new_import
      post :import
      patch :bulk_activate
      patch :bulk_disable
      delete :bulk_destroy
    end
  end
  resources :loan_statuses, &soft_disable_routes
  resources :products, &soft_disable_routes
  resources :shgs do
    collection do
      get :export
      patch :bulk_activate
      patch :bulk_disable
      delete :bulk_destroy
    end

    member do
      patch :activate
      patch :disable
      patch :approve
      patch :return_for_correction
      patch :reject
    end
  end
  resources :shg_members do
    collection do
      get :export
      patch :bulk_activate
      patch :bulk_disable
      delete :bulk_destroy
    end

    member do
      patch :activate
      patch :disable
    end
  end
  resources :visit_records do
    collection do
      get :export
      patch :bulk_disable
      delete :bulk_destroy
    end

    member do
      patch :disable
      patch :approve
      patch :return_for_correction
      patch :reject
    end
  end
  resources :shg_loans do
    member do
      get :passbook
    end

    collection do
      get :export
      get :import, action: :new_import
      post :import
      patch :bulk_disable
      delete :bulk_destroy
    end

    member do
      patch :disable
    end

    resources :shg_loan_emis, only: [] do
      member do
        patch :pay
      end
    end
  end
end
