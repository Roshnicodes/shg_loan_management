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
  get "profile", to: "users#profile", as: :profile
  resource :location_import, only: %i[new create]
  resource :location_export, only: :show

  resources :states
  resources :districts
  resources :blocks
  resources :villages
  resources :user_types
  resources :users do
    member do
      patch :reset_password
      patch :disable
    end

    collection do
      get :export
      get :import, action: :new_import
      post :import
      patch :bulk_disable
      delete :bulk_destroy
    end
  end
  resources :loan_statuses
  resources :products
  resources :shgs do
    collection do
      get :export
      delete :bulk_destroy
    end

    member do
      patch :approve
      patch :return_for_correction
      patch :reject
    end
  end
  resources :shg_members do
    collection do
      get :export
      delete :bulk_destroy
    end
  end
  resources :visit_records do
    collection do
      get :export
      delete :bulk_destroy
    end

    member do
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
      delete :bulk_destroy
    end

    resources :shg_loan_emis, only: [] do
      member do
        patch :pay
      end
    end
  end
end
